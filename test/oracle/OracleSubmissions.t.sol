// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {PriceLoomOracle} from "src/oracle/PriceLoomOracle.sol";
import {
    NoData,
    WrongRound,
    Expired,
    OutOfBounds,
    DuplicateSubmission,
    NotOperator,
    FeedMismatch
} from "src/oracle/PriceLoomOracle.sol";
import {OracleTypes} from "src/oracle/PriceLoomTypes.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// Submission/round lifecycle tests covering:
// - Opening rounds, finalization at maxSubmissions, median computation
// - Batch submission path and finalization
// - Timeout-driven finalization at quorum
// - Stale price roll-forward below quorum
// - Error paths: WrongRound, Expired, OutOfBounds, DuplicateSubmission
contract OracleSubmissionsTest is Test {
    PriceLoomOracle internal oracle;

    bytes32 internal FEED = keccak256("AR/byte");
    address internal admin;
    address[] internal ops;
    uint256[] internal pkeys;

    function setUp() public {
        admin = address(this);
        oracle = new PriceLoomOracle(admin);

        // Prepare operators
        ops = new address[](3);
        pkeys = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            (ops[i], pkeys[i]) = makeAddrAndKey(string(abi.encodePacked("op", i)));
        }

        OracleTypes.FeedConfig memory cfg = OracleTypes.FeedConfig({
            decimals: 8,
            minSubmissions: 2,
            maxSubmissions: 3,
            trim: 0,
            heartbeatSec: 0, // disable for predictable testing
            deviationBps: 100, // 1%
            timeoutSec: 900,
            minPrice: int256(-1e20),
            maxPrice: int256(1e20),
            description: "AR/byte"
        });

        oracle.createFeed(FEED, cfg, ops);
    }

    // No open or finalized rounds at start
    function test_initialRoundState() public view {
        assertEq(oracle.currentRoundId(FEED), 0);
        assertEq(oracle.latestFinalizedRoundId(FEED), 0);
    }

    // Finalize at maxSubmissions; verify median, timestamp
    function test_submitAndFinalize() public {
        // Round 1 starts with first submission
        uint80 roundId = 1;
        int256 price1 = 100e8;
        int256 price2 = 102e8;

        // op1 submits
        _submit(0, roundId, price1);
        assertEq(oracle.currentRoundId(FEED), roundId, "Round should have started");

        // op2 submits
        _submit(1, roundId, price2);

        // Not yet finalized (minSubmissions = 2, maxSubmissions = 3) → NO_DATA
        vm.expectRevert(NoData.selector);
        oracle.latestRoundData(FEED);

        // op3 submits, which should trigger finalization
        int256 price3 = 101e8;
        _submit(2, roundId, price3);

        (uint80 latestRoundId2, int256 answer,, uint256 updatedAt,) = oracle.latestRoundData(FEED);
        assertEq(latestRoundId2, roundId, "Round not finalized");
        assertEq(answer, 101e8, "Median incorrect"); // Median of [100, 101, 102]
        assertEq(updatedAt, block.timestamp, "Timestamp wrong");
    }

    // Batch path should validate, record, and finalize in one call
    function test_submitBatchAndFinalize() public {
        uint80 roundId = 1;
        int256[] memory prices = new int256[](3);
        prices[0] = 100e8;
        prices[1] = 102e8;
        prices[2] = 101e8;

        PriceLoomOracle.PriceSubmission[] memory subs = new PriceLoomOracle.PriceSubmission[](3);
        bytes[] memory sigs = new bytes[](3);

        for (uint256 i = 0; i < 3; i++) {
            subs[i] = PriceLoomOracle.PriceSubmission({
                feedId: FEED,
                roundId: roundId,
                answer: prices[i],
                validUntil: block.timestamp + 60
            });
            bytes32 digest = oracle.getTypedDataHash(subs[i]);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(pkeys[i], digest);
            sigs[i] = abi.encodePacked(r, s, v);
        }

        oracle.submitSignedBatch(FEED, subs, sigs);

        (uint80 latestRoundId, int256 answer,, uint256 updatedAt,) = oracle.latestRoundData(FEED);
        assertEq(latestRoundId, roundId, "Round not finalized");
        assertEq(answer, 101e8, "Median incorrect"); // Median of [100, 101, 102]
        assertEq(updatedAt, block.timestamp, "Timestamp wrong");
    }

    // With minSubmissions reached but not max, timeout should finalize to current median
    function test_quorumAndTimeout() public {
        uint80 roundId = 1;
        int256 price1 = 100e8;
        int256 price2 = 102e8;

        // op1 submits
        _submit(0, roundId, price1);

        // op2 submits
        _submit(1, roundId, price2);

        // Round should not be finalized yet (minSubmissions = 2, maxSubmissions = 3)
        vm.expectRevert(NoData.selector);
        oracle.latestRoundData(FEED);

        // Advance time to trigger timeout
        vm.warp(block.timestamp + 901);

        // Now, anyone can trigger the finalization
        oracle.poke(FEED);

        (uint80 latestRoundId2, int256 answer,, uint256 updatedAt,) = oracle.latestRoundData(FEED);
        assertEq(latestRoundId2, roundId, "Round not finalized after timeout");
        assertEq(answer, 101e8, "Median incorrect"); // Median of [100, 102]
        assertEq(updatedAt, block.timestamp, "Timestamp wrong");
    }

    // Below quorum on timeout should roll forward stale answer preserving answeredInRound and updatedAt
    function test_stalePriceForwarding() public {
        // First, establish a price in round 1
        uint80 roundId1 = 1;
        _submit(0, roundId1, 100e8);
        _submit(1, roundId1, 101e8);
        _submit(2, roundId1, 102e8);

        (uint80 latestRoundId1, int256 answer1,,,) = oracle.latestRoundData(FEED);
        assertEq(latestRoundId1, 1, "Round 1 not finalized");
        assertEq(answer1, 101e8, "Median for round 1 incorrect");

        // Now, start round 2 but don't meet quorum
        uint80 roundId2 = 2;
        _submit(0, roundId2, 200e8);

        // Advance time to trigger timeout
        vm.warp(block.timestamp + 901);

        // Poke the oracle to handle the timeout
        oracle.poke(FEED);

        (uint80 latestRoundId2, int256 answer2,, uint256 updatedAt, uint80 answeredInRound) =
            oracle.latestRoundData(FEED);
        assertEq(latestRoundId2, 2, "Round 2 not finalized");
        assertEq(answer2, 101e8, "Price should be forwarded from round 1");
        assertEq(answeredInRound, 1, "answeredInRound should be 1");
        assertTrue(oracle.isStale(FEED, 0), "Price should be stale");
    }

    // Submitting for a non-open round should revert WrongRound
    function test_revert_wrongRoundId() public {
        uint80 roundId = 2; // Round 1 is not started yet
        int256 price = 100e8;

        PriceLoomOracle.PriceSubmission memory sub = PriceLoomOracle.PriceSubmission({
            feedId: FEED,
            roundId: roundId,
            answer: price,
            validUntil: block.timestamp + 60
        });
        _submitExpectRevert(0, sub, WrongRound.selector);
    }

    // Expired signature must revert
    function test_revert_expiredSignature() public {
        uint80 roundId = 1;
        int256 price = 100e8;

        PriceLoomOracle.PriceSubmission memory sub = PriceLoomOracle.PriceSubmission({
            feedId: FEED,
            roundId: roundId,
            answer: price,
            validUntil: block.timestamp - 1
        });

        bytes32 digest = oracle.getTypedDataHash(sub);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pkeys[0], digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(Expired.selector);
        oracle.submitSigned(FEED, sub, sig);
    }

    // Answer outside configured bounds must revert
    function test_revert_outOfBounds() public {
        uint80 roundId = 1;
        int256 price = 2e20; // > maxPrice

        PriceLoomOracle.PriceSubmission memory sub = PriceLoomOracle.PriceSubmission({
            feedId: FEED,
            roundId: roundId,
            answer: price,
            validUntil: block.timestamp + 60
        });
        _submitExpectRevert(0, sub, OutOfBounds.selector);
    }

    // Same operator cannot submit twice into the same round
    function test_revert_duplicateSubmission() public {
        uint80 roundId = 1;
        int256 price = 100e8;

        _submit(0, roundId, price);

        PriceLoomOracle.PriceSubmission memory sub = PriceLoomOracle.PriceSubmission({
            feedId: FEED,
            roundId: roundId,
            answer: price,
            validUntil: block.timestamp + 60
        });
        _submitExpectRevert(0, sub, DuplicateSubmission.selector);
    }

    function test_notOperator_reverts() public {
        uint80 roundId = 1;
        int256 price = 100e8;
        (address notOp, uint256 notOpKey) = makeAddrAndKey("not-an-operator");

        PriceLoomOracle.PriceSubmission memory sub = PriceLoomOracle.PriceSubmission({
            feedId: FEED,
            roundId: roundId,
            answer: price,
            validUntil: block.timestamp + 60
        });

        bytes32 digest = oracle.getTypedDataHash(sub);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(notOpKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(NotOperator.selector);
        oracle.submitSigned(FEED, sub, sig);
    }

    function test_feedMismatch_reverts() public {
        uint80 roundId = 1;
        int256 price = 100e8;

        PriceLoomOracle.PriceSubmission memory sub = PriceLoomOracle.PriceSubmission({
            feedId: keccak256("wrong-feed"),
            roundId: roundId,
            answer: price,
            validUntil: block.timestamp + 60
        });
        _submitExpectRevert(0, sub, FeedMismatch.selector);
    }

    function test_roundFull_reverts_on_extra_submission() public {
        uint80 roundId = 1;
        _submit(0, roundId, 100e8);
        _submit(1, roundId, 101e8);
        _submit(2, roundId, 102e8);

        // Round is now full and finalized
        (address notOp,) = makeAddrAndKey("not-an-operator");
        PriceLoomOracle.PriceSubmission memory sub = PriceLoomOracle.PriceSubmission({
            feedId: FEED,
            roundId: roundId,
            answer: 103e8,
            validUntil: block.timestamp + 60
        });
        _submitExpectRevert(0, sub, WrongRound.selector);
    }

    function test_even_count_median_negative_rounding() public {
        uint80 roundId = 1;
        _submit(0, roundId, -100e8);
        _submit(1, roundId, -101e8);

        vm.warp(block.timestamp + 901);
        oracle.poke(FEED);

        (, int256 answer,,,) = oracle.latestRoundData(FEED);
        assertEq(answer, -1005e7); // (-100 - 101) / 2 = -100.5
    }

    function test_timeout_without_prior_data_keeps_NoData() public {
        uint80 roundId = 1;
        _submit(0, roundId, 100e8);

        vm.warp(block.timestamp + 901);
        oracle.poke(FEED);

        vm.expectRevert(NoData.selector);
        oracle.latestRoundData(FEED);
    }

    // Helper: sign and attempt submit expecting the provided revert selector
    function _submitExpectRevert(uint256 opIdx, PriceLoomOracle.PriceSubmission memory sub, bytes4 selector) internal {
        bytes32 digest = oracle.getTypedDataHash(sub);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pkeys[opIdx], digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.expectRevert(selector);
        oracle.submitSigned(FEED, sub, sig);
    }

    // Helper: sign and submit once for operator opIdx
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
