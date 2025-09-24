// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {OracleTypes} from "./PriceLoomTypes.sol";
import {IOracleReader} from "src/interfaces/IOracleReader.sol";
import {IOracleAdmin} from "src/interfaces/IOracleAdmin.sol";

contract PriceLoomOracle is
    AccessControl,
    Pausable,
    ReentrancyGuard,
    EIP712,
    IOracleAdmin,
    IOracleReader
{
    using ECDSA for bytes32;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FEED_ADMIN_ROLE = keccak256("FEED_ADMIN_ROLE");

    uint8 public constant MAX_OPERATORS = 31;

    // v0 EIP712 typehash (submission path will be added next)
    bytes32 public constant PRICE_SUBMISSION_TYPEHASH =
        keccak256(
            "PriceSubmission(bytes32 feedId,uint80 roundId,int256 answer,uint256 validUntil)"
        );

    modifier onlyFeedOperator(bytes32 feedId) {
        _onlyFeedOperator(feedId);
        _;
    }

    function _onlyFeedOperator(bytes32 feedId) internal view {
        require(_opIndex[feedId][msg.sender] != 0, "not operator");
    }

    // Storage
    mapping(bytes32 => OracleTypes.FeedConfig) private _feedConfig;
    mapping(bytes32 => mapping(address => uint8)) private _opIndex; // 1-based index; 0 = not an operator
    mapping(bytes32 => address[]) private _operators; // operators per feed
    mapping(bytes32 => OracleTypes.RoundData) private _latestSnapshot; // latest finalized per feed

    // Working state for open rounds (per feedId, per round)
    mapping(bytes32 => mapping(uint80 => uint256)) private _submittedBitmap; // dedupe operators (1 bit per index)
    mapping(bytes32 => mapping(uint80 => mapping(uint8 => int256)))
        private _answers; // answers[feedId][roundId][i]
    mapping(bytes32 => mapping(uint80 => uint8)) private _answerCount; // count per open round

    // Open-round tracking (utilized when we add submissions)
    mapping(bytes32 => uint80) private _latestRoundId;
    mapping(bytes32 => mapping(uint80 => uint256)) private _roundStartedAt;

    // Events
    event FeedCreated(bytes32 indexed feedId, OracleTypes.FeedConfig cfg);
    event FeedConfigUpdated(bytes32 indexed feedId, OracleTypes.FeedConfig cfg);
    event OperatorAdded(bytes32 indexed feedId, address op);
    event OperatorRemoved(bytes32 indexed feedId, address op);
    event SubmissionReceived(
        bytes32 indexed feedId,
        uint80 indexed roundId,
        address indexed operator,
        int256 answer
    );
    event RoundFinalized(
        bytes32 indexed feedId,
        uint80 indexed roundId,
        uint8 submissionCount
    );
    event PriceUpdated(
        bytes32 indexed feedId,
        int256 answer,
        uint256 updatedAt
    );

    constructor(address admin) EIP712("Price Loom", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(FEED_ADMIN_ROLE, admin);
    }

    // ============ Admin ============
    function createFeed(
        bytes32 feedId,
        OracleTypes.FeedConfig calldata cfg,
        address[] calldata operators
    ) external onlyRole(FEED_ADMIN_ROLE) {
        require(_feedConfig[feedId].decimals == 0, "Feed exists");
        _validateConfig(cfg, operators.length);
        _feedConfig[feedId] = cfg;

        if (operators.length > 0) {
            require(operators.length <= MAX_OPERATORS, "too many ops");
            _operators[feedId] = operators;
            for (uint8 i = 0; i < operators.length; i++) {
                address op = operators[i];
                require(op != address(0), "zero op");
                require(_opIndex[feedId][op] == 0, "dup op");
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
            finalized: false,
            stale: true,
            submissionCount: 0
        });

        emit FeedCreated(feedId, cfg);
    }

    function setFeedConfig(
        bytes32 feedId,
        OracleTypes.FeedConfig calldata cfg
    ) external onlyRole(FEED_ADMIN_ROLE) {
        require(_feedConfig[feedId].decimals != 0, "No feed");
        _validateConfig(cfg, _operators[feedId].length);
        _feedConfig[feedId] = cfg;
        emit FeedConfigUpdated(feedId, cfg);
    }

    function addOperator(
        bytes32 feedId,
        address op
    ) external onlyRole(FEED_ADMIN_ROLE) {
        require(_feedConfig[feedId].decimals != 0, "No feed");
        require(op != address(0), "zero op");
        require(_opIndex[feedId][op] == 0, "exists");
        require(_operators[feedId].length < MAX_OPERATORS, "max ops");
        _operators[feedId].push(op);
        _opIndex[feedId][op] = uint8(_operators[feedId].length); // 1-based
        emit OperatorAdded(feedId, op);
    }

    function removeOperator(
        bytes32 feedId,
        address op
    ) external onlyRole(FEED_ADMIN_ROLE) {
        uint8 idx1 = _opIndex[feedId][op];
        require(idx1 != 0, "not op");
        address[] storage ops = _operators[feedId];
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

    function getConfig(
        bytes32 feedId
    ) external view returns (OracleTypes.FeedConfig memory) {
        return _feedConfig[feedId];
    }

    function isOperator(
        bytes32 feedId,
        address op
    ) external view returns (bool) {
        return _opIndex[feedId][op] != 0;
    }

    function getLatestPrice(
        bytes32 feedId
    ) external view returns (int256 price, uint256 updatedAt) {
        OracleTypes.RoundData storage snap = _latestSnapshot[feedId];
        return (snap.answer, snap.updatedAt);
    }

    function latestRoundData(
        bytes32 feedId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        OracleTypes.RoundData storage snap = _latestSnapshot[feedId];
        return (
            snap.roundId,
            snap.answer,
            snap.startedAt,
            snap.updatedAt,
            snap.answeredInRound
        );
    }

    function currentRoundId(bytes32 feedId) external view returns (uint80) {
        uint80 next = _latestRoundId[feedId] + 1;
        if (_roundStartedAt[feedId][next] != 0) return next; // open round exists
        return _latestRoundId[feedId];
    }

    function isStale(
        bytes32 feedId,
        uint256 maxStalenessSec
    ) external view returns (bool) {
        OracleTypes.RoundData storage snap = _latestSnapshot[feedId];
        if (snap.updatedAt == 0) return true;
        return (block.timestamp - snap.updatedAt) > maxStalenessSec;
    }

    // EIP712
    function domainSeparatorV4() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function priceSubmissionTypehash() external pure returns (bytes32) {
        return PRICE_SUBMISSION_TYPEHASH;
    }

    function submitPrice(
        bytes32 feedId,
        int256 answer,
        uint256 validUntil
    ) external whenNotPaused nonReentrant onlyFeedOperator(feedId) {
        // basic feed + bounds checks
        OracleTypes.FeedConfig storage cfg = _feedConfig[feedId];
        require(cfg.decimals != 0, "no feed");
        require(block.timestamp <= validUntil, "expired");
        require(_withinBounds(feedId, answer), "out of bounds");

        // round selection
        uint80 latest = _latestRoundId[feedId];
        uint80 openId = latest + 1;
        bool hasOpen = _roundStartedAt[feedId][openId] != 0;

        // if no open round, only start when due (or on first ever update)
        if (!hasOpen) {
            OracleTypes.RoundData storage snap = _latestSnapshot[feedId];
            bool firstEver = (snap.updatedAt == 0);
            require(
                firstEver || _shouldStartNewRound(feedId, answer),
                "not due"
            );
            _roundStartedAt[feedId][openId] = block.timestamp;
            hasOpen = true;
        }

        // target current open round
        uint80 roundId = openId;

        // dedupe: one submission per operator per round
        uint8 opIdx = _opIndex[feedId][msg.sender]; // 1-based
        uint256 mask = (uint256(1) << (opIdx - 1));
        uint256 bitmap = _submittedBitmap[feedId][roundId];
        require(bitmap & mask == 0, "duplicate");
        _submittedBitmap[feedId][roundId] = bitmap | mask;

        // record answer
        uint8 n = _answerCount[feedId][roundId];
        _answers[feedId][roundId][n] = answer;
        _answerCount[feedId][roundId] = n + 1;

        emit SubmissionReceived(feedId, roundId, msg.sender, answer);

        // finalize if reached max submissions
        if (n + 1 == cfg.maxSubmissions) {
            _finalizeRound(feedId, roundId);
        }
    }

    function _finalizeRound(bytes32 feedId, uint80 roundId) internal {
        uint8 n = _answerCount[feedId][roundId];
        require(n > 0, "no answers");

        int256[] memory buf = new int256[](n);
        for (uint8 i = 0; i < n; i++) {
            buf[i] = _answers[feedId][roundId][i];
        }
        _insertionSort(buf, n);

        int256 median;
        if (n % 2 == 1) {
            median = buf[n / 2];
        } else {
            int256 a = buf[(n / 2) - 1];
            int256 b = buf[n / 2];
            median = _avgRoundHalfUp(a, b);
        }

        OracleTypes.RoundData storage snap = _latestSnapshot[feedId];
        snap.roundId = roundId;
        snap.answer = median;
        snap.startedAt = _roundStartedAt[feedId][roundId];
        snap.updatedAt = block.timestamp;
        snap.answeredInRound = roundId;
        snap.finalized = true;
        snap.stale = false;
        snap.submissionCount = n;

        _latestRoundId[feedId] = roundId;

        emit RoundFinalized(feedId, roundId, n);
        emit PriceUpdated(feedId, median, snap.updatedAt);
    }

    // ============ Math ================

    // average with round-half-up for non-negative values
    function _avgRoundHalfUp(
        int256 a,
        int256 b
    ) internal pure returns (int256) {
        if (a >= 0 && b >= 0) {
            return (a + b + 1) / 2;
        }
        // fallback for mixed/negative: Solidity rounds toward zero
        return (a + b) / 2;
    }

    function _insertionSort(int256[] memory arr, uint256 len) internal pure {
        for (uint256 i = 1; i < len; i++) {
            int256 key = arr[i];
            uint256 j = i;
            while (j > 0 && arr[j - 1] > key) {
                arr[j] = arr[j - 1];
                unchecked {
                    j--;
                }
            }
            arr[j] = key;
        }
    }

    // ============ Internal ============

    function _validateConfig(
        OracleTypes.FeedConfig calldata cfg,
        uint256 operatorCount
    ) internal pure {
        require(cfg.decimals > 0 && cfg.decimals <= 18, "bad decimals");
        require(cfg.maxSubmissions >= cfg.minSubmissions, "bad min/max");
        require(cfg.minSubmissions >= 1, "min >=1");
        require(cfg.maxSubmissions <= MAX_OPERATORS, "max too large");
        if (operatorCount > 0) {
            require(operatorCount <= MAX_OPERATORS, "too many ops");
        }
        require(cfg.trim == 0, "trim unsupported v0");
        require(cfg.maxPrice >= cfg.minPrice, "bounds");
    }

    // Bounds check: price within [minPrice, maxPrice]
    function _withinBounds(
        bytes32 feedId,
        int256 answer
    ) internal view returns (bool) {
        OracleTypes.FeedConfig storage cfg = _feedConfig[feedId];
        return answer >= cfg.minPrice && answer <= cfg.maxPrice;
    }

    // Absolute value helper (answers expected non-negative in v0)
    function _absInt(int256 x) internal pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }

    // Has heartbeat elapsed since last update?
    function _heartbeatElapsed(bytes32 feedId) internal view returns (bool) {
        OracleTypes.FeedConfig storage cfg = _feedConfig[feedId];
        OracleTypes.RoundData storage snap = _latestSnapshot[feedId];
        if (cfg.heartbeatSec == 0) return false;
        if (snap.updatedAt == 0) return true; // no prior answer → allow first round
        return (block.timestamp - snap.updatedAt) >= cfg.heartbeatSec;
    }

    // Does proposed answer exceed deviation threshold vs last?
    function _exceedsDeviation(
        bytes32 feedId,
        int256 proposed
    ) internal view returns (bool) {
        OracleTypes.FeedConfig storage cfg = _feedConfig[feedId];
        if (cfg.deviationBps == 0) return false;

        OracleTypes.RoundData storage snap = _latestSnapshot[feedId];
        if (snap.updatedAt == 0) return true; // no prior answer → allow first round

        uint256 lastAbs = _absInt(snap.answer);
        uint256 denom = lastAbs > 0 ? lastAbs : 1; // avoid div by zero
        uint256 diff = _absInt(proposed - snap.answer);

        // diff / last >= deviationBps / 10_000
        return (diff * 10_000) / denom >= cfg.deviationBps;
    }

    // Gate to decide if a new round should start on next submission
    function _shouldStartNewRound(
        bytes32 feedId,
        int256 proposed
    ) internal view returns (bool) {
        return _heartbeatElapsed(feedId) || _exceedsDeviation(feedId, proposed);
    }
}
