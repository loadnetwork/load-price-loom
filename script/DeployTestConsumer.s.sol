// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";
import {TestPriceConsumer} from "src/examples/TestPriceConsumer.sol";

/// Deploys a minimal consumer bound to a given adapter.
/// Env:
///  - ADAPTER: address of a deployed PriceLoomAggregatorV3Adapter
contract DeployTestConsumer is Script {
    function run() external {
        address adapter = vm.envAddress("ADAPTER");
        vm.startBroadcast();
        TestPriceConsumer consumer = new TestPriceConsumer(AggregatorV3Interface(adapter));
        vm.stopBroadcast();
        console2.log("TestPriceConsumer deployed:");
        console2.logAddress(address(consumer));
    }
}
