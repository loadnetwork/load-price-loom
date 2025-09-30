// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {PriceLoomAggregatorV3Adapter} from "./PriceLoomAggregatorV3Adapter.sol";
import {IOracleReader} from "../interfaces/IOracleReader.sol";
import {OracleTypes} from "../oracle/PriceLoomTypes.sol";

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

error FeedNotFound();

contract PriceLoomAdapterFactory {
    IOracleReader public immutable oracle;

    event AdapterDeployed(bytes32 indexed feedId, address adapter);

    constructor(IOracleReader oracle_) {
        oracle = oracle_;
    }

    function deployAdapter(bytes32 feedId) external returns (address adapter) {
        OracleTypes.FeedConfig memory cfg = oracle.getConfig(feedId);
        if (cfg.decimals == 0) revert FeedNotFound();
        adapter = address(new PriceLoomAggregatorV3Adapter(oracle, feedId));
        emit AdapterDeployed(feedId, adapter);
    }

    function deployAdapterDeterministic(bytes32 feedId) external returns (address adapter) {
        OracleTypes.FeedConfig memory cfg = oracle.getConfig(feedId);
        if (cfg.decimals == 0) revert FeedNotFound();
        adapter = address(new PriceLoomAggregatorV3Adapter{salt: feedId}(oracle, feedId));
        emit AdapterDeployed(feedId, adapter);
    }

    /// @notice Predict the deterministic adapter address for a feedId using CREATE2.
    /// @dev Uses salt = feedId and constructor args (oracle, feedId).
    function computeAdapterAddress(bytes32 feedId) external view returns (address predicted) {
        // CREATE2 address prediction must hash the actual init code bytes:
        // init_code = creationCode || abi.encode(constructor_args)
        bytes32 initCodeHash =
            keccak256(bytes.concat(type(PriceLoomAggregatorV3Adapter).creationCode, abi.encode(oracle, feedId)));
        predicted = Create2.computeAddress(feedId, initCodeHash, address(this));
    }
}
