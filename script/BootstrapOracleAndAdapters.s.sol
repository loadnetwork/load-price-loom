// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {PriceLoomOracle} from "src/oracle/PriceLoomOracle.sol";
import {OracleTypes} from "src/oracle/PriceLoomTypes.sol";
import {PriceLoomAdapterFactory} from "src/adapter/PriceLoomAdapterFactory.sol";

contract BootstrapOracleAndAdapters is Script {
    using stdJson for string;

    function run() external {
        address admin = vm.envAddress("ADMIN");
        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        string memory file = vm.envOr("FEEDS_FILE", string("feeds/feeds.json"));
        string memory json = vm.readFile(file);

        // Count feeds by checking for the .id field specifically
        uint256 n = 0;
        for (uint256 i = 0; i < 1000; i++) {
            string memory idPath = string.concat(".feeds[", vm.toString(i), "].id");
            try vm.parseJsonString(json, idPath) returns (string memory) {
                n++;
            } catch {
                break;
            }
        }

        vm.startBroadcast(adminPrivateKey);
        PriceLoomOracle oracle = new PriceLoomOracle(admin);
        PriceLoomAdapterFactory factory = new PriceLoomAdapterFactory(oracle);
        console2.log("Oracle :");
        console2.logAddress(address(oracle));
        console2.log("Factory:");
        console2.logAddress(address(factory));

        string memory outPath = "out/e2e-addresses.txt";
        vm.writeFile(outPath, "");
        vm.writeLine(outPath, string.concat("oracle=", vm.toString(address(oracle))));
        vm.writeLine(outPath, string.concat("factory=", vm.toString(address(factory))));

        for (uint256 i = 0; i < n; i++) {
            string memory idx = vm.toString(i);
            string memory basePath = string.concat(".feeds[", idx, "]");

            string memory idStr = json.readString(string.concat(basePath, ".id"));
            bytes32 feedId = keccak256(abi.encodePacked(idStr));

            uint8 decimals = uint8(json.readUint(string.concat(basePath, ".decimals")));
            uint8 minSubs = uint8(json.readUint(string.concat(basePath, ".minSubmissions")));
            uint8 maxSubs = uint8(json.readUint(string.concat(basePath, ".maxSubmissions")));
            uint32 heartbeat = uint32(json.readUint(string.concat(basePath, ".heartbeatSec")));
            uint32 deviation = uint32(json.readUint(string.concat(basePath, ".deviationBps")));
            uint32 timeout = uint32(json.readUint(string.concat(basePath, ".timeoutSec")));
            int256 minPrice = vm.parseInt(json.readString(string.concat(basePath, ".minPrice")));
            int256 maxPrice = vm.parseInt(json.readString(string.concat(basePath, ".maxPrice")));
            string memory desc = json.readString(string.concat(basePath, ".description"));
            address[] memory ops = json.readAddressArray(string.concat(basePath, ".operators"));

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
            console2.log("Created feed:", idStr);
            console2.logBytes32(feedId);

            address predicted = factory.computeAdapterAddress(feedId);
            address deployed = factory.deployAdapterDeterministic(feedId);
            console2.log("Adapter predicted:");
            console2.logAddress(predicted);
            console2.log("Adapter deployed :");
            console2.logAddress(deployed);

            vm.writeLine(
                outPath,
                string.concat(
                    "feed=",
                    idStr,
                    " feedId=",
                    vm.toString(feedId),
                    " adapterPredicted=",
                    vm.toString(predicted),
                    " adapter=",
                    vm.toString(deployed)
                )
            );
        }

        vm.stopBroadcast();
    }
}
