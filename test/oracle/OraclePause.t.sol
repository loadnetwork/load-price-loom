// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {PriceLoomOracle} from "src/oracle/PriceLoomOracle.sol";
import {OracleTypes} from "src/oracle/PriceLoomTypes.sol";

contract OraclePauseTest is Test {
    PriceLoomOracle internal oracle;

    bytes32 internal FEED = keccak256("AR/byte");
    address internal admin;
    address[] internal ops;
    uint256[] internal pkeys;
    address internal pauser;

    function setUp() public {
        admin = makeAddr("admin");
        pauser = makeAddr("pauser");
        oracle = new PriceLoomOracle(admin);

        // Grant roles from admin
        vm.startPrank(admin);
        oracle.grantRole(oracle.PAUSER_ROLE(), pauser);
        oracle.grantRole(oracle.FEED_ADMIN_ROLE(), admin);
        vm.stopPrank();

        // Prepare operators
        ops = new address[](3);
        pkeys = new uint256[](3);
        (ops[0], pkeys[0]) = makeAddrAndKey("op1");
        (ops[1], pkeys[1]) = makeAddrAndKey("op2");
        (ops[2], pkeys[2]) = makeAddrAndKey("op3");

        vm.prank(admin);
        oracle.createFeed(FEED, _defaultConfig(), ops);
    }

    function test_pause_blocks_submissions() public {
        vm.prank(pauser);
        oracle.pause();
        // Precompute signature outside expectRevert to ensure the next call reverts
        bytes memory sig = _signSubmission(0, 1, 100);
        vm.expectRevert();
        oracle.submitSigned(FEED, _createSubmission(1, 100), sig);
    }

    function test_unpause_restores_submissions() public {
        vm.prank(pauser);
        oracle.pause();

        vm.prank(pauser);
        oracle.unpause();

        oracle.submitSigned(FEED, _createSubmission(1, 100), _signSubmission(0, 1, 100));
        assertEq(oracle.latestFinalizedRoundId(FEED), 0);
    }

    function test_role_enforcement_for_admin_and_pauser() public {
        address stranger = makeAddr("stranger");
        // Stranger without PAUSER_ROLE cannot pause
        vm.prank(stranger);
        vm.expectRevert();
        oracle.pause();

        // Pauser can pause
        vm.prank(pauser);
        oracle.pause();

        // Stranger without PAUSER_ROLE cannot unpause
        vm.prank(stranger);
        vm.expectRevert();
        oracle.unpause();

        // Pauser can unpause
        vm.prank(pauser);
        oracle.unpause();
    }

    function test_poke_callable_while_paused() public {
        vm.prank(pauser);
        oracle.pause();
        oracle.poke(FEED);
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
    }
}
