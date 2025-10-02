// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {PriceLoomOracle} from "src/oracle/PriceLoomOracle.sol";

/// Pokes feeds defined in JSON (handles timed-out rounds).
/// Env:
///  - ORACLE: address of deployed PriceLoomOracle (IOracleReader)
///  - FEEDS_FILE: path to JSON file (default: feeds.json)
contract PokeFeedsFromJson is Script {
    using stdJson for string;

    function run() external {
        address oracleAddr = vm.envAddress("ORACLE");
        PriceLoomOracle oracle = PriceLoomOracle(oracleAddr);

        string memory file = vm.envOr("FEEDS_FILE", string("feeds/feeds.json"));
        string memory json = vm.readFile(file);

        uint256 n = json.readUint(".feeds.length");
        console2.log("Feeds to poke:");
        console2.logUint(n);

        vm.startBroadcast();
        for (uint256 i = 0; i < n; i++) {
            string memory idx = vm.toString(i);
            string memory idStr = json.readString(string.concat(".feeds[", idx, "].id"));
            bytes32 feedId = keccak256(abi.encodePacked(idStr));
            oracle.poke(feedId);
            console2.log("Poked:");
            console2.logString(idStr);
            console2.logBytes32(feedId);
        }
        vm.stopBroadcast();
    }
}
