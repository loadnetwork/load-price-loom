// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";
import {IOracleReader} from "src/interfaces/IOracleReader.sol";
import {PriceLoomAdapterFactory} from "src/adapter/PriceLoomAdapterFactory.sol";

/// Deploys the Adapter Factory bound to a core oracle.
/// Env:
///  - ORACLE: address of deployed PriceLoomOracle
contract DeployFactory is Script {
    function run() external {
        address oracleAddr = vm.envAddress("ORACLE");
        vm.startBroadcast();
        PriceLoomAdapterFactory factory = new PriceLoomAdapterFactory(IOracleReader(oracleAddr));
        vm.stopBroadcast();
        console2.log("Factory deployed:");
        console2.logAddress(address(factory));
    }
}
