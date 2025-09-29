// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {PriceLoomOracle} from "src/oracle/PriceLoomOracle.sol";
import {OracleTypes} from "src/oracle/PriceLoomTypes.sol";

contract DeployOracleWithTestFeeds is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployer);

        // 1. Deploy the Oracle
        PriceLoomOracle oracle = new PriceLoomOracle(deployer);
        console2.log("PriceLoomOracle deployed at:");
        console2.logAddress(address(oracle));

        // 2. Define a common set of operators
        address[] memory operators = new address[](3);
        operators[0] = vm.addr(vm.envUint("OPERATOR_1_PK"));
        operators[1] = vm.addr(vm.envUint("OPERATOR_2_PK"));
        operators[2] = vm.addr(vm.envUint("OPERATOR_3_PK"));

        // 3. Define feed configs
        OracleTypes.FeedConfig memory arBytesConfig = OracleTypes.FeedConfig({
            decimals: 18,
            minSubmissions: 2,
            maxSubmissions: 3,
            trim: 0,
            heartbeatSec: 3600, // 1 hour
            deviationBps: 100, // 1%
            timeoutSec: 900, // 15 minutes
            minPrice: 1, // Prevent zero price
            maxPrice: 1e24, // 1M AR/byte in 1e18
            description: "AR/byte"
        });

        OracleTypes.FeedConfig memory arUsdConfig = OracleTypes.FeedConfig({
            decimals: 8,
            minSubmissions: 2,
            maxSubmissions: 3,
            trim: 0,
            heartbeatSec: 3600, // 1 hour
            deviationBps: 200, // 2%
            timeoutSec: 900, // 15 minutes
            minPrice: 1_00000000, // $1
            maxPrice: 10000_00000000, // $10,000
            description: "AR/USD"
        });

        // 4. Create feeds
        bytes32 arBytesFeedId = keccak256("AR/byte");
        oracle.createFeed(arBytesFeedId, arBytesConfig, operators);
        console2.log("Created feed 'AR/byte' with ID:");
        console2.logBytes32(arBytesFeedId);

        bytes32 arUsdFeedId = keccak256("AR/USD");
        oracle.createFeed(arUsdFeedId, arUsdConfig, operators);
        console2.log("Created feed 'AR/USD' with ID:");
        console2.logBytes32(arUsdFeedId);

        vm.stopBroadcast();
    }
}
