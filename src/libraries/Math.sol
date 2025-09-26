// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library Math {
    // average with round-half-up
    function avgRoundHalfUp(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        // safe from overflow; equivalent to (a + b + 1) / 2
        return (a >> 1) + (b >> 1) + (((a & 1) + (b & 1) + 1) >> 1);
    }

    // Absolute value of signed int as uint; handles INT_MIN
    function absSignedToUint(int256 x) internal pure returns (uint256) {
        if (x >= 0) return uint256(x);
        // INT_MIN's absolute value is 2^255
        if (x == type(int256).min) {
            return (uint256(1) << 255);
        }
        return uint256(-x);
    }

    // Absolute difference between two signed ints, as uint; overflow-safe
    function absDiffSignedToUint(
        int256 a,
        int256 b
    ) internal pure returns (uint256) {
        unchecked {
            // Bias both to unsigned in a monotonic way by flipping the sign bit
            uint256 ua = uint256(a) ^ (uint256(1) << 255);
            uint256 ub = uint256(b) ^ (uint256(1) << 255);
            return ua > ub ? ua - ub : ub - ua;
        }
    }

    // average with round-half-up for signed ints
    // - If both non-negative: round half up as unsigned
    // - If both negative: apply half-up on magnitudes, then negate
    // - If mixed signs: use trunc toward zero (x + (y - x)/2)
    function avgRoundHalfUpSigned(
        int256 a,
        int256 b
    ) internal pure returns (int256) {
        if (a >= 0 && b >= 0) {
            uint256 au = uint256(a);
            uint256 bu = uint256(b);
            return int256(avgRoundHalfUp(au, bu));
        }
        if (a <= 0 && b <= 0) {
            uint256 au = absSignedToUint(a);
            uint256 bu = absSignedToUint(b);
            uint256 mu = avgRoundHalfUp(au, bu);
            // If mu equals 2^255, return INT_MIN directly to avoid casting overflow
            if (mu == (uint256(1) << 255)) return type(int256).min;
            return -int256(mu);
        }
        // mixed signs: (a + b) cannot overflow; division truncates toward zero
        return (a + b) / 2;
    }
}
