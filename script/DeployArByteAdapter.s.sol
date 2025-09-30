// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";
import {IOracleReader} from "src/interfaces/IOracleReader.sol";
import {PriceLoomAggregatorV3Adapter} from "src/adapter/PriceLoomAggregatorV3Adapter.sol";

// Usage:
//   ORACLE=<oracle_address> forge script script/DeployArByteAdapter.s.sol:DeployArByteAdapter \
//       --rpc-url <RPC> --broadcast --verify -vvvv
// The script deploys an AggregatorV3-compatible adapter for the AR/byte feedId.

contract DeployArByteAdapter is Script {
    // feedId for "AR/byte"
    bytes32 constant FEED_ID = keccak256(abi.encodePacked("AR/byte"));

    function run() external {
        address oracleAddr = vm.envAddress("ORACLE");
        IOracleReader oracle = IOracleReader(oracleAddr);

        vm.startBroadcast();
        PriceLoomAggregatorV3Adapter adapter = new PriceLoomAggregatorV3Adapter(oracle, FEED_ID);
        vm.stopBroadcast();

        console2.log("Adapter deployed for AR/byte feedId:");
        console2.logAddress(address(adapter));
    }
}
