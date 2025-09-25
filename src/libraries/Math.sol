// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library Math {
    // average with round-half-up
    function avgRoundHalfUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a + b + 1) / 2;
    }
}
