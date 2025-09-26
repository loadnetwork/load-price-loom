// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {Math} from "src/libraries/Math.sol";

contract MathLibTest is Test {
    function test_absSignedToUint_basic() public pure {
        assertEq(Math.absSignedToUint(int256(0)), 0);
        assertEq(Math.absSignedToUint(int256(42)), 42);
        assertEq(Math.absSignedToUint(int256(-42)), 42);
    }

    function test_absSignedToUint_intMin() public pure {
        // 2^255
        uint256 expected = (uint256(1) << 255);
        assertEq(Math.absSignedToUint(type(int256).min), expected);
    }

    function test_avgRoundHalfUpSigned_pos() public pure {
        assertEq(Math.avgRoundHalfUpSigned(1, 2), 2);
        assertEq(Math.avgRoundHalfUpSigned(2, 4), 3);
        assertEq(Math.avgRoundHalfUpSigned(3, 3), 3);
    }

    function test_avgRoundHalfUpSigned_neg() public pure {
        // For equal negatives, result is the same negative
        assertEq(Math.avgRoundHalfUpSigned(-3, -3), -3);
        // Mix different negatives
        assertEq(Math.avgRoundHalfUpSigned(-2, -4), -3);
    }

    function test_avgRoundHalfUpSigned_intMinPath() public pure {
        // Both negative and magnitudes average to 2^255 triggers INT_MIN path
        // Using intMin and intMin yields intMin
        assertEq(Math.avgRoundHalfUpSigned(type(int256).min, type(int256).min), type(int256).min);
    }

    function test_absDiffSignedToUint() public pure {
        assertEq(Math.absDiffSignedToUint(10, 7), 3);
        assertEq(Math.absDiffSignedToUint(-10, -7), 3);
        assertEq(Math.absDiffSignedToUint(-10, 7), 17);
        assertEq(Math.absDiffSignedToUint(10, -7), 17);
    }
}

