// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {EfficientHashLib as EHash} from "@solady-utils/EfficientHashLib.sol";

import {OracleTypes} from "./PriceLoomTypes.sol";
import {IOracleReader} from "src/interfaces/IOracleReader.sol";
import {IOracleAdmin} from "src/interfaces/IOracleAdmin.sol";

import {Sort} from "src/libraries/Sort.sol";
import {Math} from "src/libraries/Math.sol";
import {Math as OZMath} from "@openzeppelin/contracts/utils/math/Math.sol";

// EIP-712 struct hashing is implemented inline using OZ EIP712 utilities.

// Custom errors for cheaper, typed reverts.
error AdminZero();
error ZeroFeedId();
error FeedExists();
error MinGreaterThanOps();
error TooManyOps();
error ZeroOperator();
error DuplicateOperator();
error NoFeed();
error OpenRound();
error DecimalsImmutable();
error OperatorAlreadyExists();
error NotOperator();
error MaxOperatorsReached();
error QuorumGreaterThanOps();
error NoData();
error BadRoundId();
error HistoryEvicted();
error FeedMismatch();
error Expired();
error OutOfBounds();
error WrongRound();
error RoundFull();
error DuplicateSubmission();
error DuplicateInBatch();
error LengthMismatch();
error EmptyBatch();
error NoAnswers();
error BadDecimals();
error BadMinMax();
error MinSubmissionsTooSmall();
error MaxSubmissionsTooLarge();
error MaxGreaterThanOperators();
error TrimUnsupported();
error BoundsInvalid();
error MinPriceTooLow();
error MaxPriceTooHigh();
error DescriptionTooLong();
error NoGating();
error NotDue();

contract PriceLoomOracle is AccessControl, Pausable, ReentrancyGuard, EIP712, IOracleAdmin, IOracleReader {
    using ECDSA for bytes32;

    /// @notice Role for pausing and unpausing submissions. Recommended: multisig.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Role for managing feed configurations and operators. Recommended: multisig.
    bytes32 public constant FEED_ADMIN_ROLE = keccak256("FEED_ADMIN_ROLE");

    uint8 public constant MAX_OPERATORS = 31;
    /// @dev Power-of-two capacity for efficient ring buffer indexing via bitwise AND.
    uint256 internal constant HISTORY_CAPACITY = 128;
    uint256 internal constant HISTORY_MASK = HISTORY_CAPACITY - 1;

    // Note: Direct submissions require EIP-712 signatures; no direct-only operator function is exposed.

    // Storage
    mapping(bytes32 => OracleTypes.FeedConfig) private _feedConfig;
    mapping(bytes32 => mapping(address => uint8)) private _opIndex; // 1-based index; 0 = not an operator
    mapping(bytes32 => address[]) private _operators; // operators per feed
    mapping(bytes32 => OracleTypes.RoundData) private _latestSnapshot; // latest finalized per feed
    mapping(bytes32 => mapping(uint256 => OracleTypes.RoundData)) private _history; // ring buffer via mask

    // Working state for open rounds (per feedId, per round)
    mapping(bytes32 => mapping(uint80 => uint256)) private _submittedBitmap; // dedupe operators (1 bit per index)
    mapping(bytes32 => mapping(uint80 => mapping(uint8 => int256))) private _answers; // answers[feedId][roundId][i]
    mapping(bytes32 => mapping(uint80 => uint8)) private _answerCount; // count per open round

    // Open-round tracking (utilized when we add submissions)
    mapping(bytes32 => uint80) private _latestRoundId;
    mapping(bytes32 => mapping(uint80 => uint256)) private _roundStartedAt;

    // Events
    event FeedCreated(bytes32 indexed feedId, OracleTypes.FeedConfig cfg);
    event FeedConfigUpdated(bytes32 indexed feedId, OracleTypes.FeedConfig cfg);
    event OperatorAdded(bytes32 indexed feedId, address op);
    event OperatorRemoved(bytes32 indexed feedId, address op);
    event SubmissionReceived(bytes32 indexed feedId, uint80 indexed roundId, address indexed operator, int256 answer);
    event RoundFinalized(bytes32 indexed feedId, uint80 indexed roundId, uint8 submissionCount);
    event RoundStarted(bytes32 indexed feedId, uint80 indexed roundId, uint256 startedAt);
    event PriceUpdated(bytes32 indexed feedId, int256 answer, uint256 updatedAt);

    event StalePriceRolledForward(bytes32 indexed feedId, uint80 indexed roundId);

    constructor(address admin) EIP712("Price Loom", "1") {
        if (admin == address(0)) revert AdminZero();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(FEED_ADMIN_ROLE, admin);
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    // ============ Admin ============
    function createFeed(bytes32 feedId, OracleTypes.FeedConfig calldata cfg, address[] calldata operators)
        external
        onlyRole(FEED_ADMIN_ROLE)
    {
        if (feedId == bytes32(0)) revert ZeroFeedId();
        if (_feedConfig[feedId].decimals != 0) revert FeedExists();
        if (cfg.minSubmissions > operators.length) revert MinGreaterThanOps();
        _validateConfig(cfg, operators.length);
        _feedConfig[feedId] = cfg;

        if (operators.length > 0) {
            if (operators.length > MAX_OPERATORS) revert TooManyOps();
            _operators[feedId] = operators;
            for (uint8 i = 0; i < operators.length; i++) {
                address op = operators[i];
                if (op == address(0)) revert ZeroOperator();
                if (_opIndex[feedId][op] != 0) revert DuplicateOperator();
                _opIndex[feedId][op] = i + 1; // 1-based
                emit OperatorAdded(feedId, op);
            }
        }

        // initialize snapshot (roundId = 0 means not yet answered)

        _latestSnapshot[feedId] = OracleTypes.RoundData({
            roundId: 0,
            answer: 0,
            startedAt: 0,
            updatedAt: 0,
            answeredInRound: 0,
            stale: true,
            submissionCount: 0
        });

        emit FeedCreated(feedId, cfg);
    }

    function setFeedConfig(bytes32 feedId, OracleTypes.FeedConfig calldata cfg) external onlyRole(FEED_ADMIN_ROLE) {
        OracleTypes.FeedConfig storage prev = _feedConfig[feedId];
        if (prev.decimals == 0) revert NoFeed();
        if (_hasOpenRound(feedId)) revert OpenRound();
        // Decimals are immutable per feed
        if (cfg.decimals != prev.decimals) revert DecimalsImmutable();
        _validateConfig(cfg, _operators[feedId].length);
        _feedConfig[feedId] = cfg;
        emit FeedConfigUpdated(feedId, cfg);
    }

    function addOperator(bytes32 feedId, address op) external onlyRole(FEED_ADMIN_ROLE) {
        if (_feedConfig[feedId].decimals == 0) revert NoFeed();
        if (_hasOpenRound(feedId)) revert OpenRound();
        if (op == address(0)) revert ZeroOperator();
        if (_opIndex[feedId][op] != 0) revert OperatorAlreadyExists();
        if (_operators[feedId].length >= MAX_OPERATORS) revert MaxOperatorsReached();
        _operators[feedId].push(op);
        _opIndex[feedId][op] = uint8(_operators[feedId].length); // 1-based
        emit OperatorAdded(feedId, op);
    }

    function removeOperator(bytes32 feedId, address op) external onlyRole(FEED_ADMIN_ROLE) {
        uint8 idx1 = _opIndex[feedId][op];
        if (idx1 == 0) revert NotOperator();
        if (_hasOpenRound(feedId)) revert OpenRound();
        OracleTypes.FeedConfig storage cfg = _feedConfig[feedId];
        address[] storage ops = _operators[feedId];
        // enforce invariants post-removal to avoid bricking rounds
        uint256 newCount = ops.length - 1;
        if (newCount < cfg.minSubmissions) revert QuorumGreaterThanOps();
        if (newCount < cfg.maxSubmissions) revert MaxGreaterThanOperators();
        uint256 idx = uint256(idx1 - 1);
        uint256 last = ops.length - 1;
        address lastOp = ops[last];
        ops[idx] = lastOp;
        ops.pop();
        _opIndex[feedId][op] = 0;
        if (lastOp != op) {
            _opIndex[feedId][lastOp] = uint8(idx + 1);
        }
        emit OperatorRemoved(feedId, op);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ============ Views ============

    function getConfig(bytes32 feedId) external view returns (OracleTypes.FeedConfig memory) {
        return _feedConfig[feedId];
    }

    function isOperator(bytes32 feedId, address op) external view returns (bool) {
        return _opIndex[feedId][op] != 0;
    }

    function getLatestPrice(bytes32 feedId) external view returns (int256 price, uint256 updatedAt) {
        OracleTypes.RoundData storage snap = _latestSnapshot[feedId];
        if (snap.updatedAt == 0) revert NoData();
        return (snap.answer, snap.updatedAt);
    }

    function latestRoundData(bytes32 feedId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        OracleTypes.RoundData storage snap = _latestSnapshot[feedId];
        if (snap.updatedAt == 0) revert NoData();
        return (snap.roundId, snap.answer, snap.startedAt, snap.updatedAt, snap.answeredInRound);
    }

    function getRoundData(bytes32 feedId, uint80 roundId)
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        if (roundId == 0) revert BadRoundId();
        uint256 idx = (uint256(roundId) - 1) & HISTORY_MASK;
        OracleTypes.RoundData storage r = _history[feedId][idx];
        if (r.roundId != roundId) revert HistoryEvicted();
        return (r.roundId, r.answer, r.startedAt, r.updatedAt, r.answeredInRound);
    }

    function currentRoundId(bytes32 feedId) external view returns (uint80) {
        uint80 next = _latestRoundId[feedId] + 1;
        if (_roundStartedAt[feedId][next] != 0) return next; // open round exists
        return _latestRoundId[feedId];
    }

    function latestFinalizedRoundId(bytes32 feedId) external view returns (uint80) {
        return _latestRoundId[feedId];
    }

    /// @notice Returns true if the latest snapshot should be treated as stale.
    /// @dev Returns true if no data exists yet; if the snapshot was rolled forward on timeout;
    ///      or if the age exceeds `maxStalenessSec`.
    function isStale(bytes32 feedId, uint256 maxStalenessSec) external view returns (bool) {
        OracleTypes.RoundData storage snap = _latestSnapshot[feedId];
        return (snap.updatedAt == 0 || snap.stale || (block.timestamp - snap.updatedAt) > maxStalenessSec);
    }

    // Operator introspection (for ops tooling)
    function operatorCount(bytes32 feedId) external view returns (uint256) {
        return _operators[feedId].length;
    }

    function getOperators(bytes32 feedId) external view returns (address[] memory out) {
        address[] storage ops = _operators[feedId];
        out = new address[](ops.length);
        for (uint256 i = 0; i < ops.length; i++) {
            out[i] = ops[i];
        }
    }

    // EIP-712
    struct PriceSubmission {
        bytes32 feedId;
        uint80 roundId;
        int256 answer;
        uint256 validUntil;
    }

    bytes32 public constant PRICE_SUBMISSION_TYPEHASH =
        keccak256("PriceSubmission(bytes32 feedId,uint80 roundId,int256 answer,uint256 validUntil)");

    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function priceSubmissionTypehash() external pure returns (bytes32) {
        return PRICE_SUBMISSION_TYPEHASH;
    }

    // Optimized struct hash builder for EIP-712 PriceSubmission using Solady's EfficientHashLib.
    // Equivalent to: keccak256(abi.encode(PRICE_SUBMISSION_TYPEHASH, feedId, roundId, answer, validUntil))
    function _priceSubmissionStructHash(PriceSubmission calldata sub) internal pure returns (bytes32) {
        bytes32[] memory buf = EHash.malloc(5);
        buf = EHash.set(buf, 0, PRICE_SUBMISSION_TYPEHASH);
        buf = EHash.set(buf, 1, sub.feedId);
        buf = EHash.set(buf, 2, bytes32(uint256(sub.roundId)));
        buf = EHash.set(buf, 3, bytes32(uint256(sub.answer)));
        buf = EHash.set(buf, 4, bytes32(sub.validUntil));
        return EHash.hash(buf);
    }

    /// @notice Returns the EIP-712 typed data hash for a PriceSubmission.
    /// Useful for off-chain signing and test harnesses.
    function getTypedDataHash(PriceSubmission calldata sub) external view returns (bytes32) {
        bytes32 structHash = _priceSubmissionStructHash(sub);
        return _hashTypedDataV4(structHash);
    }

    // Maintenance function to process a timed-out open round.
    // Callable even while paused. For incident freeze, pause and avoid calling `poke`
    // so state does not progress; for maintenance during pause, call `poke` as needed.
    function poke(bytes32 feedId) external nonReentrant {
        _handleTimeoutIfNeeded(feedId);
    }

    function submitSigned(bytes32 feedId, PriceSubmission calldata sub, bytes calldata sig)
        external
        whenNotPaused
        nonReentrant
    {
        // basic feed + bounds checks
        OracleTypes.FeedConfig storage cfg = _feedConfig[feedId];
        if (cfg.decimals == 0) revert NoFeed();
        if (sub.feedId != feedId) revert FeedMismatch();
        if (block.timestamp > sub.validUntil) revert Expired();
        if (!_withinBounds(feedId, sub.answer, cfg)) revert OutOfBounds();

        // recover signer and ensure it is an operator
        bytes32 structHash = _priceSubmissionStructHash(sub);
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, sig);
        uint8 opIdx = _opIndex[feedId][signer];
        if (opIdx == 0) revert NotOperator();

        // Handle timed-out open round first (finalize at quorum or roll stale)
        _handleTimeoutIfNeeded(feedId);

        // determine open round id
        uint80 latest = _latestRoundId[feedId];
        uint80 openId = latest + 1;
        bool hasOpen = _roundStartedAt[feedId][openId] != 0;

        if (!hasOpen) {
            // no open round: must be due to start a new one
            OracleTypes.RoundData storage snap = _latestSnapshot[feedId];
            bool firstEver = (snap.updatedAt == 0);
            if (!(firstEver || _shouldStartNewRound(feedId, sub.answer, snap, cfg))) revert NotDue();
            // ensure signed round matches the one we are about to open
            if (sub.roundId != openId) revert WrongRound();
            _roundStartedAt[feedId][openId] = block.timestamp;
            emit RoundStarted(feedId, openId, block.timestamp);
        } else {
            // open round exists: signature must target it
            if (sub.roundId != openId) revert WrongRound();
        }

        uint8 n = _answerCount[feedId][openId];
        if (n >= cfg.maxSubmissions) revert RoundFull();

        // dedupe signer per round
        uint256 mask = (uint256(1) << (opIdx - 1));
        uint256 bitmap = _submittedBitmap[feedId][openId];
        if (bitmap & mask != 0) revert DuplicateSubmission();
        _submittedBitmap[feedId][openId] = bitmap | mask;

        // record answer
        _answers[feedId][openId][n] = sub.answer;
        _answerCount[feedId][openId] = n + 1;

        emit SubmissionReceived(feedId, openId, signer, sub.answer);

        // finalize if reached max submissions
        if (n + 1 == cfg.maxSubmissions) {
            _finalizeRound(feedId, openId);
        }
    }

    function submitSignedBatch(bytes32 feedId, PriceSubmission[] calldata subs, bytes[] calldata sigs)
        external
        whenNotPaused
        nonReentrant
    {
        if (subs.length != sigs.length) revert LengthMismatch();
        OracleTypes.FeedConfig storage cfg = _feedConfig[feedId];
        if (cfg.decimals == 0) revert NoFeed();

        // Handle timed-out open round first (finalize at quorum or roll stale)
        _handleTimeoutIfNeeded(feedId);

        // determine open round id
        uint80 latest = _latestRoundId[feedId];
        uint80 openId = latest + 1;
        bool hasOpen = _roundStartedAt[feedId][openId] != 0;

        OracleTypes.RoundData storage snap = _latestSnapshot[feedId];

        if (!hasOpen) {
            // allow opening only when due; gate based on first item
            if (subs.length == 0) revert EmptyBatch();
            PriceSubmission calldata first = subs[0];

            bool firstEver = (snap.updatedAt == 0);
            if (!(firstEver || _shouldStartNewRound(feedId, first.answer, snap, cfg))) {
                revert NotDue();
            }

            if (first.feedId != feedId) revert FeedMismatch();
            if (first.roundId != openId) revert WrongRound();
            if (block.timestamp > first.validUntil) revert Expired();
            if (!_withinBounds(feedId, first.answer, cfg)) revert OutOfBounds();

            _roundStartedAt[feedId][openId] = block.timestamp;
            emit RoundStarted(feedId, openId, block.timestamp);
        }

        uint8 n_ = _answerCount[feedId][openId];
        if (n_ >= cfg.maxSubmissions) revert RoundFull();

        // dedupe signers within this batch using operator index bits
        uint256 batchMask = 0;
        uint256 onchainBitmap = _submittedBitmap[feedId][openId];

        for (uint256 i = 0; i < subs.length; i++) {
            PriceSubmission calldata sub = subs[i];

            // per-item sanity
            if (sub.feedId != feedId) revert FeedMismatch();
            if (sub.roundId != openId) revert WrongRound();
            if (block.timestamp > sub.validUntil) revert Expired();
            if (!_withinBounds(feedId, sub.answer, cfg)) revert OutOfBounds();

            // recover signer and map to operator index
            bytes32 structHash = _priceSubmissionStructHash(sub);
            bytes32 digest = _hashTypedDataV4(structHash);
            address signer = ECDSA.recover(digest, sigs[i]);
            uint8 opIdx = _opIndex[feedId][signer];
            if (opIdx == 0) revert NotOperator();

            uint256 bit = (uint256(1) << (opIdx - 1));

            // reject duplicates within batch and across on-chain bitmap
            if (batchMask & bit != 0) revert DuplicateInBatch();
            batchMask |= bit;

            if (onchainBitmap & bit != 0) revert DuplicateSubmission();

            // record answer
            if (n_ >= cfg.maxSubmissions) revert RoundFull();
            _answers[feedId][openId][n_] = sub.answer;
            n_++;

            emit SubmissionReceived(feedId, openId, signer, sub.answer);

            if (n_ == cfg.maxSubmissions) {
                _submittedBitmap[feedId][openId] = onchainBitmap | batchMask;
                _answerCount[feedId][openId] = n_;
                _finalizeRound(feedId, openId);
                return;
            }
        }
        _submittedBitmap[feedId][openId] = onchainBitmap | batchMask;
        _answerCount[feedId][openId] = n_;
    }

    function _finalizeRound(bytes32 feedId, uint80 roundId) internal {
        uint8 n = _answerCount[feedId][roundId];
        if (n == 0) revert NoAnswers();

        int256[] memory buf = new int256[](n);
        for (uint8 i = 0; i < n; i++) {
            buf[i] = _answers[feedId][roundId][i];
        }

        Sort.insertionSort(buf);

        int256 median;
        if (n % 2 == 1) {
            median = buf[n / 2];
        } else {
            int256 a = buf[(n / 2) - 1];
            int256 b = buf[n / 2];
            median = Math.avgRoundHalfUpSigned(a, b);
        }

        OracleTypes.RoundData storage snap = _latestSnapshot[feedId];
        snap.roundId = roundId;
        snap.answer = median;
        snap.startedAt = _roundStartedAt[feedId][roundId];
        snap.updatedAt = block.timestamp;
        snap.answeredInRound = roundId;
        snap.stale = false;
        snap.submissionCount = n;

        _latestRoundId[feedId] = roundId;

        emit RoundFinalized(feedId, roundId, n);
        emit PriceUpdated(feedId, median, snap.updatedAt);

        // Store snapshot in ring buffer history
        {
            uint256 idx = (uint256(roundId) - 1) & HISTORY_MASK;
            OracleTypes.RoundData storage slot = _history[feedId][idx];
            slot.roundId = snap.roundId;
            slot.answer = snap.answer;
            slot.startedAt = snap.startedAt;
            slot.updatedAt = snap.updatedAt;
            slot.answeredInRound = snap.answeredInRound;
            slot.stale = snap.stale;
            slot.submissionCount = snap.submissionCount;
        }

        // Clear working state for this round to prevent unbounded storage growth
        _clearRound(feedId, roundId, n);
    }

    /**
     * @dev Clears the working storage for a finalized round to save gas.
     * Deletes the submission bitmap, answers, answer count, and start time for the given round.
     * This is critical to prevent unbounded storage growth over the contract's lifetime.
     * @param feedId The feed to clear the round for.
     * @param roundId The round to clear.
     * @param submissionCount The number of submissions in the round, used to iterate and clear answers.
     */
    function _clearRound(bytes32 feedId, uint80 roundId, uint8 submissionCount) internal {
        delete _submittedBitmap[feedId][roundId];
        for (uint8 i = 0; i < submissionCount; i++) {
            delete _answers[feedId][roundId][i];
        }
        delete _answerCount[feedId][roundId];
        delete _roundStartedAt[feedId][roundId];
    }

    // ============ Internal ============

    function _hasOpenRound(bytes32 feedId) internal view returns (bool) {
        uint80 openId = _latestRoundId[feedId] + 1;
        return _roundStartedAt[feedId][openId] != 0;
    }

    function _validateConfig(OracleTypes.FeedConfig calldata cfg, uint256 opCount) internal pure {
        if (!(cfg.decimals > 0 && cfg.decimals <= 18)) revert BadDecimals();
        if (cfg.maxSubmissions < cfg.minSubmissions) revert BadMinMax();
        if (cfg.minSubmissions < 1) revert MinSubmissionsTooSmall();
        if (cfg.maxSubmissions > MAX_OPERATORS) revert MaxSubmissionsTooLarge();
        if (cfg.minSubmissions > opCount) revert QuorumGreaterThanOps();
        if (opCount > 0) {
            if (opCount > MAX_OPERATORS) revert TooManyOps();
            if (cfg.maxSubmissions > opCount) revert MaxGreaterThanOperators();
        }
        if (cfg.trim != 0) revert TrimUnsupported();
        if (cfg.maxPrice < cfg.minPrice) revert BoundsInvalid();
        if (cfg.minPrice == type(int256).min) revert MinPriceTooLow();
        if (cfg.maxPrice == type(int256).max) revert MaxPriceTooHigh();
        if (bytes(cfg.description).length > 100) revert DescriptionTooLong();
        // Require at least one round gating mechanism
        if (!(cfg.heartbeatSec > 0 || cfg.deviationBps > 0)) revert NoGating();
    }

    // Bounds check: price within [minPrice, maxPrice]
    function _withinBounds(bytes32 feedId, int256 answer, OracleTypes.FeedConfig memory cfg)
        internal
        pure
        returns (bool)
    {
        return answer >= cfg.minPrice && answer <= cfg.maxPrice;
    }

    // Has heartbeat elapsed since last update?
    function _heartbeatElapsed(bytes32 feedId, OracleTypes.RoundData storage snap, OracleTypes.FeedConfig storage cfg)
        internal
        view
        returns (bool)
    {
        if (cfg.heartbeatSec == 0) return false;
        if (snap.updatedAt == 0) return true; // no prior answer → allow first round
        return (block.timestamp - snap.updatedAt) >= cfg.heartbeatSec;
    }

    // Does proposed answer exceed deviation threshold vs last?
    function _exceedsDeviation(
        bytes32 feedId,
        int256 proposed,
        OracleTypes.RoundData storage snap,
        OracleTypes.FeedConfig storage cfg
    ) internal view returns (bool) {
        if (cfg.deviationBps == 0) return false;

        if (snap.updatedAt == 0) return true; // no prior answer → allow first round

        int256 last = snap.answer;
        if (last == 0) {
            return proposed != 0; // any non-zero price deviates from zero
        }

        // absolute values (overflow-safe)
        uint256 lastAbs = Math.absSignedToUint(last);
        uint256 diff = Math.absDiffSignedToUint(proposed, last);

        // Exact and overflow-safe: (diff * 10_000) / lastAbs >= deviationBps
        return OZMath.mulDiv(diff, 10_000, lastAbs) >= uint256(cfg.deviationBps);
    }

    // Gate to decide if a new round should start on next submission
    function _shouldStartNewRound(
        bytes32 feedId,
        int256 proposed,
        OracleTypes.RoundData storage snap,
        OracleTypes.FeedConfig storage cfg
    ) internal view returns (bool) {
        return _heartbeatElapsed(feedId, snap, cfg) || _exceedsDeviation(feedId, proposed, snap, cfg);
    }

    // ============ Public Helpers (off-chain ergonomics) ============

    /// @notice Returns the roundId that operators should sign for the next submission.
    /// If an open round exists, this returns that open round id. Otherwise, it returns latestFinalized + 1.
    function nextRoundId(bytes32 feedId) external view returns (uint80) {
        uint80 latest = _latestRoundId[feedId];
        uint80 openId = latest + 1;
        if (_roundStartedAt[feedId][openId] != 0) return openId;
        return openId;
    }

    /// @notice Returns whether a new round is due to start for the given proposed answer,
    /// according to heartbeat and deviation gating.
    function dueToStart(bytes32 feedId, int256 proposed) external view returns (bool) {
        return _shouldStartNewRound(feedId, proposed, _latestSnapshot[feedId], _feedConfig[feedId]);
    }

    // Timeout handling
    /**
     * @dev Handles a timed-out open round. Can be triggered by any submission or by public `poke`.
     * If an open round has existed for longer than `timeoutSec`, this function will either:
     * 1. Finalize the round if `submissionCount >= minSubmissions`.
     * 2. Roll the feed forward with a stale price if `submissionCount < minSubmissions`.
     * @param feedId The feed to check for a timed-out round.
     * @return handled True if a timeout was handled, false otherwise.
     */
    function _handleTimeoutIfNeeded(bytes32 feedId) internal returns (bool handled) {
        OracleTypes.FeedConfig storage cfg = _feedConfig[feedId];
        if (cfg.timeoutSec == 0) return false;

        uint80 openId = _latestRoundId[feedId] + 1;
        uint256 startedAt = _roundStartedAt[feedId][openId];
        if (startedAt == 0) return false; // no open round

        if (block.timestamp - startedAt < cfg.timeoutSec) return false; // not timed out

        uint8 n = _answerCount[feedId][openId];
        if (n >= cfg.minSubmissions) {
            _finalizeRound(feedId, openId);
        } else {
            // Preserve NO_DATA semantics: if there has never been a finalized answer,
            // do not roll forward a zero value. Just clear the round and keep NO_DATA.
            OracleTypes.RoundData storage last = _latestSnapshot[feedId];
            if (last.updatedAt == 0) {
                _clearRound(feedId, openId, n);
            } else {
                _rollForwardStale(feedId, openId, n);
                _clearRound(feedId, openId, n);
            }
        }
        return true;
    }

    /**
     * @dev Rolls a feed forward with a stale price when a round times out without quorum.
     * Carries the last finalized answer forward into a new round record, marks it as stale, and
     * preserves both `answeredInRound` and the previous `updatedAt`. This keeps
     * AggregatorV3-style consumers (age and freshness checks) behaving correctly.
     * @param feedId The feed being rolled forward.
     * @param roundId The new roundId being created.
     * @param submissions The number of submissions received before timeout (less than quorum).
     */
    function _rollForwardStale(bytes32 feedId, uint80 roundId, uint8 submissions) internal {
        // Carry forward previous answer, mark stale, bump latestRoundId
        OracleTypes.RoundData storage snap = _latestSnapshot[feedId];
        // Cache fields before mutation to avoid double-aliasing reads/writes
        int256 lastAnswer = snap.answer;
        uint80 lastAnsweredInRound = snap.answeredInRound;
        uint256 lastUpdatedAt = snap.updatedAt;

        snap.roundId = roundId;
        snap.answer = lastAnswer;
        snap.startedAt = _roundStartedAt[feedId][roundId];
        // Preserve previous updatedAt so age-based consumers treat this as stale
        snap.updatedAt = lastUpdatedAt;
        snap.answeredInRound = lastAnsweredInRound; // unchanged
        snap.stale = true;
        snap.submissionCount = submissions;

        _latestRoundId[feedId] = roundId;

        emit RoundFinalized(feedId, roundId, submissions);
        emit PriceUpdated(feedId, snap.answer, snap.updatedAt);
        emit StalePriceRolledForward(feedId, roundId);

        // Store snapshot in ring buffer history
        {
            uint256 idx = (uint256(roundId) - 1) & HISTORY_MASK;
            OracleTypes.RoundData storage slot = _history[feedId][idx];
            slot.roundId = snap.roundId;
            slot.answer = snap.answer;
            slot.startedAt = snap.startedAt;
            slot.updatedAt = snap.updatedAt;
            slot.answeredInRound = snap.answeredInRound;
            slot.stale = snap.stale;
            slot.submissionCount = snap.submissionCount;
        }
    }
}
