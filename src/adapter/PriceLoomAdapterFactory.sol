// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PriceLoomAggregatorV3Adapter} from "./PriceLoomAggregatorV3Adapter.sol";
import {IOracleReader} from "../interfaces/IOracleReader.sol";

contract PriceLoomAdapterFactory {
    IOracleReader public immutable oracle;

    event AdapterDeployed(bytes32 indexed feedId, address adapter);

    constructor(IOracleReader oracle_) {
        oracle = oracle_;
    }

    function deployAdapter(bytes32 feedId) external returns (address adapter) {
        adapter = address(new PriceLoomAggregatorV3Adapter(oracle, feedId));
        emit AdapterDeployed(feedId, adapter);
    }
}

