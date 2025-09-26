// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PriceLoomAggregatorV3Adapter} from "./PriceLoomAggregatorV3Adapter.sol";
import {IOracleReader} from "../interfaces/IOracleReader.sol";
import {OracleTypes} from "../oracle/PriceLoomTypes.sol";

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract PriceLoomAdapterFactory {
    IOracleReader public immutable oracle;

    event AdapterDeployed(bytes32 indexed feedId, address adapter);

    constructor(IOracleReader oracle_) {
        oracle = oracle_;
    }

    function deployAdapter(bytes32 feedId) external returns (address adapter) {
        OracleTypes.FeedConfig memory cfg = oracle.getConfig(feedId);
        require(cfg.decimals != 0, "feed not found");
        adapter = address(new PriceLoomAggregatorV3Adapter(oracle, feedId));
        emit AdapterDeployed(feedId, adapter);
    }

    function deployAdapterDeterministic(
        bytes32 feedId
    ) external returns (address adapter) {
        OracleTypes.FeedConfig memory cfg = oracle.getConfig(feedId);
        require(cfg.decimals != 0, "feed not found");
        adapter = address(
            new PriceLoomAggregatorV3Adapter{salt: feedId}(oracle, feedId)
        );
        emit AdapterDeployed(feedId, adapter);
    }

    /// @notice Predict the deterministic adapter address for a feedId using CREATE2.
    /// @dev Uses salt = feedId and constructor args (oracle, feedId).
    function computeAdapterAddress(
        bytes32 feedId
    ) external view returns (address predicted) {
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(PriceLoomAggregatorV3Adapter).creationCode,
                abi.encode(oracle, feedId)
            )
        );
        predicted = Create2.computeAddress(feedId, initCodeHash, address(this));
    }
}
