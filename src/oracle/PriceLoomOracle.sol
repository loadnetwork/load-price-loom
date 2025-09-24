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
            "PriceSubmission(bytes32 feedId, uint80 roundId, int256 answer,uint256 validUntil)"
        );

    // Storage
    mapping(bytes32 => OracleTypes.FeedConfig) private _feedConfig;
    mapping(bytes32 => mapping(address => uint8)) private _opIndex; // 1-based index; 0 = not an operator
    mapping(bytes32 => address[]) private _operators; // operators per feed
    mapping(bytes32 => OracleTypes.RoundData) private _latestSnapshot; // latest finalized per feed

    // Open-round tracking (utilized when we add submissions)
    mapping(bytes32 => uint80) private _latestRoundId;
    mapping(bytes32 => mapping(uint80 => uint256)) private _roundStartedAt;

    // Events
    event FeedCreated(bytes32 indexed feedId, OracleTypes.FeedConfig cfg);
    event FeedConfigUpdated(bytes32 indexed feedId, OracleTypes.FeedConfig cfg);
    event OperatorAdded(bytes32 indexed feedId, address op);
    event OperatorRemoved(bytes32 indexed feedId, address op);

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
}
