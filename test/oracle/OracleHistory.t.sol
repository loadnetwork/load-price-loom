// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {PriceLoomOracle} from "src/oracle/PriceLoomOracle.sol";
import {OracleTypes} from "src/oracle/PriceLoomTypes.sol";
import {HistoryEvicted} from "src/oracle/PriceLoomOracle.sol";

// History ring buffer tests.
// - Ensures data older than 128 rounds is evicted and reverts with HistoryEvicted
// - Ensures latest rounds remain retrievable
contract OracleHistoryTest is Test {
    PriceLoomOracle internal oracle;

    bytes32 internal FEED = keccak256("AR/byte");
    address[] internal ops;
    uint256[] internal pkeys;

    function setUp() public {
        oracle = new PriceLoomOracle(address(this));

        // Single-operator config to finalize each round in 1 submission
        ops = new address[](1);
        pkeys = new uint256[](1);
        (ops[0], pkeys[0]) = makeAddrAndKey("op0");

        OracleTypes.FeedConfig memory cfg = OracleTypes.FeedConfig({
            decimals: 8,
            minSubmissions: 1,
            maxSubmissions: 1,
            trim: 0,
            heartbeatSec: 0,
            deviationBps: 1, // 0.01%
            timeoutSec: 900,
            minPrice: int256(0),
            maxPrice: int256(1e20),
            description: "AR/byte"
        });
        oracle.createFeed(FEED, cfg, ops);
    }

    // After pushing > HISTORY_CAPACITY (128) rounds, the earliest should be evicted
    function test_ringBufferEviction_after128() public {
        uint80 rounds = 130;
        int256 price = 100e8;
        for (uint80 r = 1; r <= rounds; r++) {
            _submit(0, r, price);
            // bump price ~2% to exceed 0.01% threshold and allow next round gating
            price = price + (price / 50);
        }

        // Round 1 should be evicted from 128-slot ring buffer
        vm.expectRevert(HistoryEvicted.selector);
        oracle.getRoundData(FEED, 1);

        // Latest round should be available
        (uint80 rid,,,,) = oracle.getRoundData(FEED, rounds);
        assertEq(rid, rounds, "latest round missing");
    }

    // Helper: sign and submit once to finalize single-op rounds
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
