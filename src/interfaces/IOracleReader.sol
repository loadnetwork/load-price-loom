// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OracleTypes} from "src/oracle/PriceLoomTypes.sol";

interface IOracleReader {
    function version() external view returns (uint256);

    function getLatestPrice(
        bytes32 feedId
    ) external view returns (int256 price, uint256 updatedAt);

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
        );

    function getRoundData(
        bytes32 feedId,
        uint80 roundId
    )
        external
        view
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        );

    function getConfig(
        bytes32 feedId
    ) external view returns (OracleTypes.FeedConfig memory);

    function isOperator(
        bytes32 feedId,
        address op
    ) external view returns (bool);

    function currentRoundId(bytes32 feedId) external view returns (uint80);

    function isStale(
        bytes32 feedId,
        uint256 maxStalenessSec
    ) external view returns (bool);

    // Helpers for off-chain operator ergonomics
    function nextRoundId(bytes32 feedId) external view returns (uint80);

    function dueToStart(bytes32 feedId, int256 proposed) external view returns (bool);
}
