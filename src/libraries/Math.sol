// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library Math {
    // average with round-half-up
    function avgRoundHalfUp(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return (a + b + 1) / 2;
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
            uint256 au = uint256(-a);
            uint256 bu = uint256(-b);
            uint256 mu = avgRoundHalfUp(au, bu);
            return -int256(mu);
        }
        // mixed signs; safe average without overflow
        return a + (b - a) / 2;
    }
}
