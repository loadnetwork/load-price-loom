// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {PriceLoomOracle} from "src/oracle/PriceLoomOracle.sol";
import {OracleTypes} from "src/oracle/PriceLoomTypes.sol";

contract OracleGatingTest is Test {
    PriceLoomOracle internal oracle;

    bytes32 internal FEED = keccak256("AR/byte");
    address[] internal ops;
    uint256[] internal pkeys;

    function setUp() public {
        oracle = new PriceLoomOracle(address(this));

        ops = new address[](1);
        pkeys = new uint256[](1);
        (ops[0], pkeys[0]) = makeAddrAndKey("op0");
    }

    function test_deviationThreshold_equalTriggers() public {
        OracleTypes.FeedConfig memory cfg = OracleTypes.FeedConfig({
            decimals: 8,
            minSubmissions: 1,
            maxSubmissions: 1,
            trim: 0,
            heartbeatSec: 0,
            deviationBps: 100, // 1%
            timeoutSec: 900,
            minPrice: int256(0),
            maxPrice: int256(1e20),
            description: "AR/byte"
        });
        oracle.createFeed(FEED, cfg, ops);

        // Round 1: 100e8
        _submit(0, 1, 100e8);
        // Round 2: exactly +1% → should be allowed to start
        _submit(0, 2, 101e8);

        (uint80 rid,,,,) = oracle.latestRoundData(FEED);
        assertEq(rid, 2, "round 2 should finalize");
    }

    function test_heartbeatElapsed_equalTriggers() public {
        OracleTypes.FeedConfig memory cfg = OracleTypes.FeedConfig({
            decimals: 8,
            minSubmissions: 1,
            maxSubmissions: 1,
            trim: 0,
            heartbeatSec: 10,
            deviationBps: 0,
            timeoutSec: 900,
            minPrice: int256(0),
            maxPrice: int256(1e20),
            description: "AR/byte"
        });
        oracle.createFeed(FEED, cfg, ops);

        _submit(0, 1, 100e8);
        // Warp exactly heartbeatSec
        vm.warp(block.timestamp + 10);
        // Same price, but heartbeat elapsed → new round allowed
        _submit(0, 2, 100e8);

        (uint80 rid,,,,) = oracle.latestRoundData(FEED);
        assertEq(rid, 2, "round 2 should finalize after heartbeat");
    }

    function _submit(uint256 opIdx, uint80 roundId, int256 answer) internal {
        PriceLoomOracle.PriceSubmission memory sub = PriceLoomOracle.PriceSubmission({
            feedId: FEED,
            roundId: roundId,
            answer: answer,
            validUntil: block.timestamp + 60
        });
        bytes32 digest = oracle.getTypedDataHash(sub);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pkeys[opIdx], digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        oracle.submitSigned(FEED, sub, sig);
    }
}
