// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {PriceLoomAdapterFactory} from "src/adapter/PriceLoomAdapterFactory.sol";

/// Deploy deterministic adapters via factory for feeds defined in JSON.
/// Env:
///  - FACTORY: address of deployed PriceLoomAdapterFactory
///  - FEEDS_FILE: path to JSON file (default: feeds.json)
/// Feeds file uses the same shape as CreateFeedsFromJson.s.sol (uses .feeds[i].id)
contract DeployDeterministicAdaptersFromJson is Script {
    using stdJson for string;

    function run() external {
        address factoryAddr = vm.envAddress("FACTORY");
        PriceLoomAdapterFactory factory = PriceLoomAdapterFactory(factoryAddr);

        string memory file = vm.envOr("FEEDS_FILE", string("feeds/feeds.json"));
        string memory json = vm.readFile(file);

        uint256 n = json.readUint(".feeds.length");
        console2.log("Adapters to deploy:");
        console2.logUint(n);

        vm.startBroadcast();
        for (uint256 i = 0; i < n; i++) {
            string memory idx = vm.toString(i);
            string memory idStr = json.readString(string.concat(".feeds[", idx, "].id"));
            bytes32 feedId = keccak256(abi.encodePacked(idStr));

            address predicted = factory.computeAdapterAddress(feedId);
            address deployed = factory.deployAdapterDeterministic(feedId);

            console2.log("Feed:");
            console2.logString(idStr);
            console2.log("Predicted:");
            console2.logAddress(predicted);
            console2.log("Deployed :");
            console2.logAddress(deployed);
        }
        vm.stopBroadcast();
    }
}
