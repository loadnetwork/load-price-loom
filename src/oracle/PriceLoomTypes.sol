// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library OracleTypes {
    struct FeedConfig {
        uint8 decimals; // default 18
        uint8 minSubmissions; // default 3 (quorum)
        uint8 maxSubmissions; // default 5 (operators)
        uint8 trim; // reserved (0 for v0)
        uint32 heartbeatSec;
        uint32 deviationBps; // e.g., 50 = 0.5%
        uint32 timeoutSec;
        int256 minPrice; // inclusive, scaled by `decimals`
        int256 maxPrice; // inclusive, scaled by `decimals`
        string description; // e.g., "AR/byte"
    }

    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
        bool stale;
        uint8 submissionCount;
    }
}
