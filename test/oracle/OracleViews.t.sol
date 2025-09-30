// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {PriceLoomOracle} from "src/oracle/PriceLoomOracle.sol";
import {NoData, BadRoundId} from "src/oracle/PriceLoomOracle.sol";
import {OracleTypes} from "src/oracle/PriceLoomTypes.sol";

contract OracleViewsTest is Test {
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

    function test_getLatestPrice_latestRoundData_NoData() public {
        vm.expectRevert(NoData.selector);
        oracle.getLatestPrice(FEED);

        vm.expectRevert(NoData.selector);
        oracle.latestRoundData(FEED);
    }

    function test_getRoundData_round0_reverts() public {
        vm.expectRevert(BadRoundId.selector);
        oracle.getRoundData(FEED, 0);
    }

    function test_currentRoundId_and_nextRoundId_semantics() public {
        assertEq(oracle.currentRoundId(FEED), 0);
        assertEq(oracle.nextRoundId(FEED), 1);

        // Start a round
        oracle.submitSigned(FEED, _createSubmission(1, 100), _signSubmission(0, 1, 100));

        assertEq(oracle.currentRoundId(FEED), 1);
        assertEq(oracle.nextRoundId(FEED), 1);
    }

    function test_dueToStart_variants() public {
        // First round is always due
        assertTrue(oracle.dueToStart(FEED, 100));

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

        // Not due with same price (no heartbeat, no deviation)
        assertFalse(oracle.dueToStart(FEED, 101));

        // Due by heartbeat
        vm.warp(block.timestamp + 3601);
        assertTrue(oracle.dueToStart(FEED, 100));

        // Due by deviation
        vm.warp(block.timestamp - 3600);
        assertTrue(oracle.dueToStart(FEED, 200));
    }

    function test_getOperators_contents_before_after_mutations() public {
        address[] memory initialOps = oracle.getOperators(FEED);
        assertEq(initialOps.length, 3);
        assertEq(initialOps[0], ops[0]);
        assertEq(initialOps[1], ops[1]);
        assertEq(initialOps[2], ops[2]);

        oracle.addOperator(FEED, makeAddr("op4"));
        address[] memory afterAdd = oracle.getOperators(FEED);
        assertEq(afterAdd.length, 4);
        assertEq(afterAdd[3], makeAddr("op4"));

        oracle.removeOperator(FEED, ops[0]);
        address[] memory afterRemove = oracle.getOperators(FEED);
        assertEq(afterRemove.length, 3);
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
            minSubmissions: 1, // Set to 1 for easier testing
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
