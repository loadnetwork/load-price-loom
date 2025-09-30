# Consumer Guide (DeFi-Compatible)

This guide describes how to safely consume Price Loom oracle data in a style familiar to DeFi engineers used to Chainlink’s AggregatorV3.

## Core Accessors
- `latestRoundData(feedId) -> (roundId, answer, startedAt, updatedAt, answeredInRound)`
- `getLatestPrice(feedId) -> (answer, updatedAt)`
- `isStale(feedId, maxStalenessSec) -> bool`

## Freshness & Staleness Checks
Price Loom implements a “stale roll‑forward” on timeout below quorum:
- The previous finalized `answer` is carried forward to the next `roundId`.
- `stale` flag is set to true for the snapshot.
- `answeredInRound` is preserved (remains the previous round id).
- `updatedAt` is preserved (remains the previous timestamp).

This ensures standard CL‑style consumers behave correctly without special cases.

### On-Chain Consumption Example

Below is a complete example of a smart contract that safely consumes a price from a Price Loom feed via the `AggregatorV3Interface` adapter.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";

contract PriceConsumer {
    AggregatorV3Interface internal immutable priceFeed;
    uint256 internal constant MAX_PRICE_AGE = 3600; // 1 hour

    event PriceUsed(int256 price);

    constructor(address feedAdapterAddress) {
        priceFeed = AggregatorV3Interface(feedAdapterAddress);
    }

    function getSecurePrice() public view returns (int256) {
        (
            uint80 roundId,
            int256 answer,
            /* uint256 startedAt */,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        // --- Security Checks ---

        // 1. Check for invalid round or price
        require(answer > 0, "Price must be positive");
        require(roundId > 0, "Round ID must be valid");

        // 2. Check for stale data (age)
        require(block.timestamp - updatedAt <= MAX_PRICE_AGE, "Price is too old");

        // 3. Check if the round is complete
        // This is the most important check for a push-based oracle.
        // It ensures you are not using an in-progress or stale, rolled-forward price.
        require(answeredInRound >= roundId, "Round is not complete");

        return answer;
    }

    function performActionWithPrice() external {
        int256 currentPrice = getSecurePrice();
        // ... your contract logic here ...
        emit PriceUsed(currentPrice);
    }
}
```

## Operator Ergonomics (Off‑chain)
When preparing submissions off‑chain:
- Determine the round to sign for: `nextRoundId(feedId)`.
- Check if a new round should start for your proposed price: `dueToStart(feedId, proposed)`.
- Sign the EIP‑712 `PriceSubmission` typed data: `(feedId, roundId, answer, validUntil)`.

## Adapters
The `PriceLoomAggregatorV3Adapter` exposes an AggregatorV3‑compatible surface for a single `feedId`.
- Before first data, it reverts with `"No data present"` to match Chainlink behavior.
- All the freshness and staleness patterns above apply equally via the adapter.

