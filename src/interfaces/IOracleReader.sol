// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OracleTypes} from "src/oracle/PriceLoomTypes.sol";

/// @notice Read-only interface for Price Loom oracle feeds.
/// @dev Semantics align with AggregatorV3 where applicable. Notably, during a stale
///      roll-forward (timeout below quorum), the oracle preserves the previous
///      `updatedAt` and `answeredInRound` while incrementing `roundId` and marking
///      the snapshot as stale. Consumers relying on age checks and/or
///      `answeredInRound == roundId` will correctly detect staleness.
interface IOracleReader {
    function version() external view returns (uint256);

    function getLatestPrice(bytes32 feedId) external view returns (int256 price, uint256 updatedAt);

    /// @notice Latest round snapshot for a feed.
    /// @dev Reverts with `NO_DATA` before the first finalized round. During stale
    ///      roll-forward, `roundId` is incremented but `answeredInRound` and `updatedAt`
    ///      reflect the last finalized round, enabling standard staleness checks.
    function latestRoundData(bytes32 feedId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function getRoundData(bytes32 feedId, uint80 roundId)
        external
        view
        returns (uint80, int256, uint256, uint256, uint80);

    function getConfig(bytes32 feedId) external view returns (OracleTypes.FeedConfig memory);

    function isOperator(bytes32 feedId, address op) external view returns (bool);

    function currentRoundId(bytes32 feedId) external view returns (uint80);

    /// @notice Convenience helper to determine if the latest snapshot is stale.
    /// @dev Returns true if there is no data yet, if the snapshot is explicitly
    ///      marked stale (rolled forward), or if `block.timestamp - updatedAt` exceeds
    ///      the provided threshold.
    function isStale(bytes32 feedId, uint256 maxStalenessSec) external view returns (bool);

    // Helpers for off-chain operator ergonomics
    function nextRoundId(bytes32 feedId) external view returns (uint80);

    function dueToStart(bytes32 feedId, int256 proposed) external view returns (bool);
}
