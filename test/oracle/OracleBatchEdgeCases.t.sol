// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {PriceLoomOracle} from "src/oracle/PriceLoomOracle.sol";
import {
    DuplicateInBatch,
    DuplicateSubmission,
    LengthMismatch,
    EmptyBatch,
    OutOfBounds,
    Expired,
    NotDue
} from "src/oracle/PriceLoomOracle.sol";
import {OracleTypes} from "src/oracle/PriceLoomTypes.sol";

contract OracleBatchEdgeCasesTest is Test {
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
        (ops[0], pkeys[0]) = makeAddrAndKey("op1");
        (ops[1], pkeys[1]) = makeAddrAndKey("op2");
        (ops[2], pkeys[2]) = makeAddrAndKey("op3");

        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        oracle.createFeed(FEED, cfg, ops);
    }

    function test_batch_duplicate_in_batch() public {
        PriceLoomOracle.PriceSubmission[] memory subs = new PriceLoomOracle.PriceSubmission[](2);
        subs[0] = _createSubmission(1, 100);
        subs[1] = _createSubmission(1, 100);

        bytes[] memory sigs = new bytes[](2);
        sigs[0] = _signSubmission(0, 1, 100);
        sigs[1] = _signSubmission(0, 1, 100);

        vm.expectRevert(DuplicateInBatch.selector);
        oracle.submitSignedBatch(FEED, subs, sigs);
    }

    function test_batch_duplicate_against_onchain_bitmap() public {
        // First submission
        oracle.submitSigned(FEED, _createSubmission(1, 100), _signSubmission(0, 1, 100));

        // Batch with duplicate
        PriceLoomOracle.PriceSubmission[] memory subs = new PriceLoomOracle.PriceSubmission[](1);
        subs[0] = _createSubmission(1, 100);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = _signSubmission(0, 1, 100);

        vm.expectRevert(DuplicateSubmission.selector);
        oracle.submitSignedBatch(FEED, subs, sigs);
    }

    function test_batch_lengthMismatch_and_empty() public {
        PriceLoomOracle.PriceSubmission[] memory subs = new PriceLoomOracle.PriceSubmission[](1);
        subs[0] = _createSubmission(1, 100);
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = _signSubmission(0, 1, 100);
        sigs[1] = _signSubmission(1, 1, 100);

        vm.expectRevert(LengthMismatch.selector);
        oracle.submitSignedBatch(FEED, subs, sigs);

        PriceLoomOracle.PriceSubmission[] memory emptySubs = new PriceLoomOracle.PriceSubmission[](0);
        bytes[] memory emptySigs = new bytes[](0);
        vm.expectRevert(EmptyBatch.selector);
        oracle.submitSignedBatch(FEED, emptySubs, emptySigs);
    }

    function test_batch_outOfBounds_and_expired_items() public {
        PriceLoomOracle.PriceSubmission[] memory subs = new PriceLoomOracle.PriceSubmission[](2);
        subs[0] = _createSubmission(1, 100);
        subs[1] = _createSubmission(1, 1e21); // out of bounds

        bytes[] memory sigs = new bytes[](2);
        sigs[0] = _signSubmission(0, 1, 100);
        sigs[1] = _signSubmission(1, 1, 1e21);

        vm.expectRevert(OutOfBounds.selector);
        oracle.submitSignedBatch(FEED, subs, sigs);

        // Expired
        subs[1] = _createSubmission(1, 100);
        sigs[1] = _signSubmission(1, 1, 100);
        vm.warp(block.timestamp + 120);

        vm.expectRevert(Expired.selector);
        oracle.submitSignedBatch(FEED, subs, sigs);
    }

    function test_notDue_on_batch_first_item() public {
        // Finalize a round
        PriceLoomOracle.PriceSubmission[] memory subs = new PriceLoomOracle.PriceSubmission[](3);
        subs[0] = _createSubmission(1, 100);
        subs[1] = _createSubmission(1, 101);
        subs[2] = _createSubmission(1, 102);

        bytes[] memory sigs = new bytes[](3);
        sigs[0] = _signSubmission(0, 1, 100);
        sigs[1] = _signSubmission(1, 1, 101);
        sigs[2] = _signSubmission(2, 1, 102);

        oracle.submitSignedBatch(FEED, subs, sigs);

        // Try to start a new round when not due
        subs = new PriceLoomOracle.PriceSubmission[](1);
        // Use the same price as last finalized median to avoid deviation triggering
        subs[0] = _createSubmission(2, 101);
        sigs = new bytes[](1);
        sigs[0] = _signSubmission(0, 2, 101);

        vm.expectRevert(NotDue.selector);
        oracle.submitSignedBatch(FEED, subs, sigs);
    }

    function _createSubmission(uint80 roundId, int256 answer)
        internal
        view
        returns (PriceLoomOracle.PriceSubmission memory)
    {
        return PriceLoomOracle.PriceSubmission({
            feedId: FEED,
            roundId: roundId,
            answer: answer,
            validUntil: block.timestamp + 60
        });
    }

    function _signSubmission(uint256 opIdx, uint80 roundId, int256 answer) internal view returns (bytes memory) {
        PriceLoomOracle.PriceSubmission memory sub = _createSubmission(roundId, answer);
        bytes32 digest = oracle.getTypedDataHash(sub);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pkeys[opIdx], digest);
        return abi.encodePacked(r, s, v);
    }

    function _defaultConfig() internal pure returns (OracleTypes.FeedConfig memory) {
        return OracleTypes.FeedConfig({
            decimals: 8,
            minSubmissions: 2,
            maxSubmissions: 3,
            trim: 0,
            heartbeatSec: 3600,
            deviationBps: 50,
            timeoutSec: 900,
            minPrice: int256(-1e20),
            maxPrice: int256(1e20),
            description: "AR/byte"
        });
    }
}
