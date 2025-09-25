// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {IOracleReader} from "../interfaces/IOracleReader.sol";
import {OracleTypes} from "../oracle/PriceLoomTypes.sol";

// One adapter per feedId. Presents Chainlink AggregatorV3Interface for compatibility.
contract PriceLoomAggregatorV3Adapter is AggregatorV3Interface {
    IOracleReader public immutable oracle;
    bytes32 public immutable feedId;

    constructor(IOracleReader oracle_, bytes32 feedId_) {
        oracle = oracle_;
        feedId = feedId_;
    }

    function decimals() external view override returns (uint8) {
        OracleTypes.FeedConfig memory cfg = oracle.getConfig(feedId);
        return cfg.decimals;
    }

    function description() external view override returns (string memory) {
        OracleTypes.FeedConfig memory cfg = oracle.getConfig(feedId);
        return cfg.description;
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 /*_roundId*/)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        // v0 core does not expose historical rounds; returning latest is acceptable for many adapters
        // but some consumers expect a revert for historical lookups. Uncomment to enforce strict behavior:
        // revert("HIST_DISABLED");
        return oracle.latestRoundData(feedId);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return oracle.latestRoundData(feedId);
    }
}

