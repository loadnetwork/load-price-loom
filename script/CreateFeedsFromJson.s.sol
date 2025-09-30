// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IOracleAdmin} from "src/interfaces/IOracleAdmin.sol";
import {OracleTypes} from "src/oracle/PriceLoomTypes.sol";

/// Creates multiple feeds from a JSON file.
/// Env:
///  - ORACLE: address of deployed PriceLoomOracle (IOracleAdmin)
///  - FEEDS_FILE: path to JSON file (default: feeds.json at repo root)
/// JSON shape (feeds.json):
/// {
///   "feeds": [
///     {
///       "id": "AR/byte",
///       "decimals": 8,
///       "minSubmissions": 2,
///       "maxSubmissions": 3,
///       "heartbeatSec": 3600,
///       "deviationBps": 50,
///       "timeoutSec": 900,
///       "minPrice": "0",
///       "maxPrice": "10000000000000000000000",
///       "description": "AR/byte",
///       "operators": ["0x...","0x..."]
///     }
///   ]
/// }
contract CreateFeedsFromJson is Script {
    using stdJson for string;

    function run() external {
        address oracleAddr = vm.envAddress("ORACLE");
        IOracleAdmin oracle = IOracleAdmin(oracleAddr);

        string memory file = vm.envOr("FEEDS_FILE", string("feeds.json"));
        string memory json = vm.readFile(file);

        uint256 n = json.readUint(".feeds.length");
        console2.log("Feeds to create:");
        console2.logUint(n);

        vm.startBroadcast();
        for (uint256 i = 0; i < n; i++) {
            string memory idx = vm.toString(i);

            string memory idStr = json.readString(string.concat(".feeds[", idx, "].id"));
            bytes32 feedId = keccak256(abi.encodePacked(idStr));

            uint8 decimals = uint8(json.readUint(string.concat(".feeds[", idx, "].decimals")));
            uint8 minSubs = uint8(json.readUint(string.concat(".feeds[", idx, "].minSubmissions")));
            uint8 maxSubs = uint8(json.readUint(string.concat(".feeds[", idx, "].maxSubmissions")));
            uint32 heartbeat = uint32(json.readUint(string.concat(".feeds[", idx, "].heartbeatSec")));
            uint32 deviation = uint32(json.readUint(string.concat(".feeds[", idx, "].deviationBps")));
            uint32 timeout = uint32(json.readUint(string.concat(".feeds[", idx, "].timeoutSec")));

            // Read big ints as strings and parse via cheatcodes
            string memory minStr = json.readString(string.concat(".feeds[", idx, "].minPrice"));
            string memory maxStr = json.readString(string.concat(".feeds[", idx, "].maxPrice"));
            int256 minPrice = vm.parseInt(minStr);
            int256 maxPrice = vm.parseInt(maxStr);

            string memory desc = json.readString(string.concat(".feeds[", idx, "].description"));
            address[] memory ops = json.readAddressArray(string.concat(".feeds[", idx, "].operators"));

            OracleTypes.FeedConfig memory cfg = OracleTypes.FeedConfig({
                decimals: decimals,
                minSubmissions: minSubs,
                maxSubmissions: maxSubs,
                trim: 0,
                heartbeatSec: heartbeat,
                deviationBps: deviation,
                timeoutSec: timeout,
                minPrice: minPrice,
                maxPrice: maxPrice,
                description: desc
            });

            oracle.createFeed(feedId, cfg, ops);
            console2.log("Created feed:");
            console2.logString(idStr);
            console2.logBytes32(feedId);
        }
        vm.stopBroadcast();
    }
}
