// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {PriceLoomOracle} from "src/oracle/PriceLoomOracle.sol";
import {
    ZeroOperator,
    OperatorAlreadyExists,
    MaxOperatorsReached,
    NoFeed,
    NotOperator,
    QuorumGreaterThanOps,
    OpenRound
} from "src/oracle/PriceLoomOracle.sol";
import {OracleTypes} from "src/oracle/PriceLoomTypes.sol";

contract OracleOperatorsTest is Test {
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

    function test_addOperator_success_and_indexing() public {
        address newOp = makeAddr("op4");
        oracle.addOperator(FEED, newOp);
        assertTrue(oracle.isOperator(FEED, newOp));
        assertEq(oracle.operatorCount(FEED), 4);
    }

    function test_addOperator_reverts_zero() public {
        vm.expectRevert(ZeroOperator.selector);
        oracle.addOperator(FEED, address(0));
    }

    function test_addOperator_reverts_duplicate() public {
        vm.expectRevert(OperatorAlreadyExists.selector);
        oracle.addOperator(FEED, ops[0]);
    }

    function test_addOperator_reverts_max_reached() public {
        // fill up operators to MAX_OPERATORS
        for (uint8 i = 3; i < 31; i++) {
            oracle.addOperator(FEED, makeAddr(string(abi.encodePacked("op", i))));
        }
        vm.expectRevert(MaxOperatorsReached.selector);
        oracle.addOperator(FEED, makeAddr("op32"));
    }

    function test_addOperator_reverts_no_feed() public {
        vm.expectRevert(NoFeed.selector);
        oracle.addOperator(keccak256("non-existent-feed"), makeAddr("op4"));
    }

    function test_removeOperator_success_compacts_index() public {
        // Adjust config to allow removal: set maxSubmissions to 2
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        cfg.maxSubmissions = 2;
        oracle.setFeedConfig(FEED, cfg);

        oracle.removeOperator(FEED, ops[1]);
        assertFalse(oracle.isOperator(FEED, ops[1]));
        assertEq(oracle.operatorCount(FEED), 2);
        // check that the last operator was moved to the removed operator's slot
        assertTrue(oracle.isOperator(FEED, ops[2]));
    }

    function test_removeOperator_reverts_not_operator() public {
        vm.expectRevert(NotOperator.selector);
        oracle.removeOperator(FEED, makeAddr("not-an-operator"));
    }

    function test_removeOperator_reverts_quorum_invariant() public {
        // First, set maxSubmissions to 2 so that one removal is allowed (3 -> 2)
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        cfg.maxSubmissions = 2;
        oracle.setFeedConfig(FEED, cfg);

        // Remove one operator successfully (3 -> 2)
        oracle.removeOperator(FEED, ops[0]);

        // Now removal to 1 would violate minSubmissions = 2
        vm.expectRevert(QuorumGreaterThanOps.selector);
        oracle.removeOperator(FEED, ops[1]);
    }

    function test_addOperator_reverts_open_round() public {
        // Start a round
        oracle.submitSigned(FEED, _createSubmission(1, 100), _signSubmission(0, 1, 100));

        vm.expectRevert(OpenRound.selector);
        oracle.addOperator(FEED, makeAddr("op4"));
    }

    function test_removeOperator_reverts_open_round() public {
        // Start a round
        oracle.submitSigned(FEED, _createSubmission(1, 100), _signSubmission(0, 1, 100));

        vm.expectRevert(OpenRound.selector);
        oracle.removeOperator(FEED, ops[1]);
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
