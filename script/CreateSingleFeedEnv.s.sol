// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IOracleAdmin} from "src/interfaces/IOracleAdmin.sol";
import {OracleTypes} from "src/oracle/PriceLoomTypes.sol";

/// Creates a single feed using environment variables.
/// Env:
///  - ORACLE: address of deployed PriceLoomOracle (IOracleAdmin)
///  - FEED_DESC: string id (e.g., "AR/byte")
///  - DECIMALS, MIN_SUBMISSIONS, MAX_SUBMISSIONS: uints
///  - HEARTBEAT_SEC, DEVIATION_BPS, TIMEOUT_SEC: uints
///  - MIN_PRICE, MAX_PRICE: string-encoded ints (to avoid overflow parsing)
///  - DESCRIPTION: string description
///  - OPERATORS_JSON: JSON array string of addresses (e.g., ["0x...","0x..."])
///    OR
///  - OPERATORS_FILE: path to JSON file containing { "operators": ["0x...", ...] }
contract CreateSingleFeedEnv is Script {
    using stdJson for string;

    function run() external {
        address oracleAddr = vm.envAddress("ORACLE");
        IOracleAdmin oracle = IOracleAdmin(oracleAddr);

        string memory idStr = vm.envString("FEED_DESC");
        bytes32 feedId = keccak256(abi.encodePacked(idStr));

        uint8 decimals = uint8(vm.envUint("DECIMALS"));
        uint8 minSubs = uint8(vm.envUint("MIN_SUBMISSIONS"));
        uint8 maxSubs = uint8(vm.envUint("MAX_SUBMISSIONS"));
        uint32 heartbeat = uint32(vm.envUint("HEARTBEAT_SEC"));
        uint32 deviation = uint32(vm.envUint("DEVIATION_BPS"));
        uint32 timeout = uint32(vm.envUint("TIMEOUT_SEC"));

        int256 minPrice = vm.parseInt(vm.envString("MIN_PRICE"));
        int256 maxPrice = vm.parseInt(vm.envString("MAX_PRICE"));
        string memory desc = vm.envString("DESCRIPTION");

        address[] memory ops = _readOperators();

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

        vm.startBroadcast();
        oracle.createFeed(feedId, cfg, ops);
        vm.stopBroadcast();
        console2.log("Created feed:");
        console2.logString(idStr);
        console2.logBytes32(feedId);
    }

    function _readOperators() internal view returns (address[] memory ops) {
        // Prefer JSON array in env var
        string memory opsJson = vm.envOr("OPERATORS_JSON", string(""));
        if (bytes(opsJson).length != 0) {
            // Wrap to parse root array via stdJson
            string memory wrapped = string.concat("{\"ops\":", opsJson, "}");
            ops = wrapped.readAddressArray(".ops");
            return ops;
        }
        // Otherwise read from a file path containing { "operators": [ ... ] }
        string memory file = vm.envOr("OPERATORS_FILE", string(""));
        if (bytes(file).length == 0) revert("OPERATORS_JSON or OPERATORS_FILE required");
        string memory json = vm.readFile(file);
        ops = json.readAddressArray(".operators");
    }
}
