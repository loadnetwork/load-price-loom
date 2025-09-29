// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {PriceLoomOracle} from "src/oracle/PriceLoomOracle.sol";
import {OracleTypes} from "src/oracle/PriceLoomTypes.sol";
import {PriceLoomAdapterFactory, FeedNotFound} from "src/adapter/PriceLoomAdapterFactory.sol";
import {PriceLoomAggregatorV3Adapter} from "src/adapter/PriceLoomAggregatorV3Adapter.sol";

contract AdapterFactoryTest is Test {
    PriceLoomOracle internal oracle;
    PriceLoomAdapterFactory internal factory;

    bytes32 internal FEED = keccak256("AR/byte");
    address[] internal ops;

    function setUp() public {
        oracle = new PriceLoomOracle(address(this));
        factory = new PriceLoomAdapterFactory(oracle);
    }

    function _createFeed() internal {
        ops = new address[](3);
        ops[0] = makeAddr("op1");
        ops[1] = makeAddr("op2");
        ops[2] = makeAddr("op3");

        OracleTypes.FeedConfig memory cfg = OracleTypes.FeedConfig({
            decimals: 8,
            minSubmissions: 3,
            maxSubmissions: 3,
            trim: 0,
            heartbeatSec: 3600,
            deviationBps: 50,
            timeoutSec: 900,
            minPrice: int256(-1e20),
            maxPrice: int256(1e20),
            description: "AR/byte"
        });
        oracle.createFeed(FEED, cfg, ops);
    }

    function test_factoryRejectsUnknownFeed() public {
        vm.expectRevert(FeedNotFound.selector);
        factory.deployAdapter(FEED);

        vm.expectRevert(FeedNotFound.selector);
        factory.deployAdapterDeterministic(FEED);
    }

    function test_deployAdapterAndQuery() public {
        _createFeed();
        address adapter = factory.deployAdapter(FEED);

        // Query via adapter
        uint8 dec = PriceLoomAggregatorV3Adapter(adapter).decimals();
        string memory desc = PriceLoomAggregatorV3Adapter(adapter).description();
        assertEq(dec, 8);
        assertEq(desc, "AR/byte");

        // latestRoundData should revert with Chainlink-style message before first data
        vm.expectRevert(bytes("No data present"));
        PriceLoomAggregatorV3Adapter(adapter).latestRoundData();
    }

    function test_deterministicAddress() public {
        _createFeed();
        address deployed = factory.deployAdapterDeterministic(FEED);

        address predicted = factory.computeAdapterAddress(FEED);
        assertEq(deployed, predicted, "CREATE2 address mismatch");
    }
}
