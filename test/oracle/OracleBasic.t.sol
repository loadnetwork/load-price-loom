// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {PriceLoomOracle} from "src/oracle/PriceLoomOracle.sol";
import {OracleTypes} from "src/oracle/PriceLoomTypes.sol";

contract OracleBasicTest is Test {
    PriceLoomOracle internal oracle;

    bytes32 internal FEED = keccak256("AR/byte");
    address internal admin;
    address[] internal ops;

    function setUp() public {
        admin = address(this);
        oracle = new PriceLoomOracle(admin);

        // Prepare operators
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

    function test_configCreated() public view {
        OracleTypes.FeedConfig memory cfg = oracle.getConfig(FEED);
        assertEq(cfg.decimals, 8);
        assertEq(cfg.minSubmissions, 3);
        assertEq(cfg.maxSubmissions, 3);
        assertEq(cfg.heartbeatSec, 3600);
        assertEq(cfg.deviationBps, 50);
        assertEq(cfg.timeoutSec, 900);
        assertEq(cfg.description, "AR/byte");
    }

    function test_operatorCount() public view {
        assertEq(oracle.operatorCount(FEED), 3);
        assertTrue(oracle.isOperator(FEED, ops[0]));
        assertTrue(oracle.isOperator(FEED, ops[1]));
        assertTrue(oracle.isOperator(FEED, ops[2]));
    }
}

