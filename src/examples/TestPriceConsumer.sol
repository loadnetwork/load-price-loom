// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";

/// @notice Minimal example consumer that reads from a Chainlink-compatible adapter.
contract TestPriceConsumer {
    AggregatorV3Interface public immutable adapter;

    constructor(AggregatorV3Interface adapter_) {
        adapter = adapter_;
    }

    function latest() external view returns (int256 answer, uint256 updatedAt) {
        (, int256 a,, uint256 u,) = adapter.latestRoundData();
        return (a, u);
    }
}
