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

    function version() external view override returns (uint256) {
        return oracle.version();
    }

    function getRoundData(
        uint80 roundId
    )
        external
        view
        override
        returns (
            uint80 roundId_,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        try oracle.getRoundData(feedId, roundId) returns (
            uint80 r,
            int256 a,
            uint256 s,
            uint256 u,
            uint80 air
        ) {
            return (r, a, s, u, air);
        } catch {
            revert("No data present");
        }
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        try oracle.latestRoundData(feedId) returns (
            uint80 _roundId,
            int256 _answer,
            uint256 _startedAt,
            uint256 _updatedAt,
            uint80 _answeredInRound
        ) {
            return (
                _roundId,
                _answer,
                _startedAt,
                _updatedAt,
                _answeredInRound
            );
        } catch {
            revert("No data present");
        }
    }
}
