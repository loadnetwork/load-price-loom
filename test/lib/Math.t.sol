// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {PriceLoomMath} from "src/libraries/PriceLoomMath.sol";

// PriceLoomMath unit tests.
// - absSignedToUint covers 0, positives, negatives, and INT_MIN edge
// - avgRoundHalfUpSigned covers positive, negative, and INT_MIN edge case
// - absDiffSignedToUint covers sign combinations
contract MathLibTest is Test {
    // 0, positive, negative
    function test_absSignedToUint_basic() public pure {
        assertEq(PriceLoomMath.absSignedToUint(int256(0)), 0);
        assertEq(PriceLoomMath.absSignedToUint(int256(42)), 42);
        assertEq(PriceLoomMath.absSignedToUint(int256(-42)), 42);
    }

    // INT_MIN absolute value equals 2^255
    function test_absSignedToUint_intMin() public pure {
        // 2^255
        uint256 expected = (uint256(1) << 255);
        assertEq(PriceLoomMath.absSignedToUint(type(int256).min), expected);
    }

    // Positive-only averages round half up
    function test_avgRoundHalfUpSigned_pos() public pure {
        assertEq(PriceLoomMath.avgRoundHalfUpSigned(1, 2), 2);
        assertEq(PriceLoomMath.avgRoundHalfUpSigned(2, 4), 3);
        assertEq(PriceLoomMath.avgRoundHalfUpSigned(3, 3), 3);
    }

    // Negative-only averages on magnitudes, then negate
    function test_avgRoundHalfUpSigned_neg() public pure {
        // For equal negatives, result is the same negative
        assertEq(PriceLoomMath.avgRoundHalfUpSigned(-3, -3), -3);
        // Mix different negatives
        assertEq(PriceLoomMath.avgRoundHalfUpSigned(-2, -4), -3);
    }

    // Edge path: both INT_MIN yields INT_MIN
    function test_avgRoundHalfUpSigned_intMinPath() public pure {
        // Both negative and magnitudes average to 2^255 triggers INT_MIN path
        // Using intMin and intMin yields intMin
        assertEq(PriceLoomMath.avgRoundHalfUpSigned(type(int256).min, type(int256).min), type(int256).min);
    }

    // Magnitude differences across sign combinations
    function test_absDiffSignedToUint() public pure {
        assertEq(PriceLoomMath.absDiffSignedToUint(10, 7), 3);
        assertEq(PriceLoomMath.absDiffSignedToUint(-10, -7), 3);
        assertEq(PriceLoomMath.absDiffSignedToUint(-10, 7), 17);
        assertEq(PriceLoomMath.absDiffSignedToUint(10, -7), 17);
    }
}
