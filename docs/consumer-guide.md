# Consumer Guide

How to safely read Price Loom oracle prices in your smart contracts.

---

## Quick Reference

### Via Chainlink-Compatible Adapter (Recommended)

```solidity
import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";

AggregatorV3Interface priceFeed = AggregatorV3Interface(adapterAddress);
(uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

// Security checks
require(answer > 0, "Invalid price");
require(block.timestamp - updatedAt <= MAX_AGE, "Stale price");
require(answeredInRound >= roundId, "Incomplete round");
```

### Direct Oracle Access

```solidity
import {IOracleReader} from "src/interfaces/IOracleReader.sol";

IOracleReader oracle = IOracleReader(oracleAddress);
bytes32 feedId = keccak256(abi.encodePacked("AR/byte"));
(uint80 roundId, int256 answer,, uint256 updatedAt,) = oracle.latestRoundData(feedId);
```

---

## Core Interface

### AggregatorV3Interface (Adapter)
- `latestRoundData() -> (roundId, answer, startedAt, updatedAt, answeredInRound)`
- `decimals() -> uint8`
- `description() -> string`
- `version() -> uint256`

### IOracleReader (Direct)
- `latestRoundData(feedId) -> (roundId, answer, startedAt, updatedAt, answeredInRound)`
- `getLatestPrice(feedId) -> (answer, updatedAt)`
- `isStale(feedId, maxStalenessSec) -> bool`
- `getConfig(feedId) -> FeedConfig`

## Freshness & Staleness Checks

### Stale Roll-Forward Behavior
Price Loom implements a "stale roll‑forward" on timeout below quorum:
- The previous finalized `answer` is carried forward to the next `roundId`.
- `stale` flag is set to true for the snapshot.
- `answeredInRound` is preserved (remains the previous round id).
- `updatedAt` is preserved (remains the previous timestamp).

This ensures standard Chainlink‑style consumers behave correctly without special cases.

### History Window (128 Rounds)
⚠️ **Important**: The oracle maintains a **128-round rolling history** per feed:
- `latestRoundData()` always works (returns most recent finalized round)
- `getRoundData(roundId)` reverts with `"No data present"` for rounds outside the 128-round window
- Historical data is evicted on a rolling basis as new rounds finalize
- **Recommendation**: Use `latestRoundData()` or the adapter for most use cases
- Only use `getRoundData()` if you specifically need historical rounds and handle eviction gracefully

**For consumers**: If your contract needs historical data, implement fallback logic for evicted rounds or cache critical data on-chain.

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

---

## Security Best Practices

1. **Always check price age**: `require(block.timestamp - updatedAt <= MAX_AGE)`
2. **Verify round completion**: `require(answeredInRound >= roundId)`
3. **Validate price range**: Check min/max bounds for your use case
4. **Handle reverts**: Wrap oracle calls in try/catch for circuit breaker patterns
5. **Monitor staleness**: Use `isStale()` for additional validation

See the example contract above for a complete secure implementation.

---

## Related Documentation

- **[Adapter Guide](./adapter-guide.md)** - Chainlink compatibility and adapter architecture
- **[Local Development Guide](./local-development-guide.md)** - Test your consumer contracts locally
- **[Deployment Cookbook](./deployment-cookbook.md)** - Deploy consumers with test examples
- **[Oracle Design](./oracle-design-v0.md)** - Technical specification and architecture

---

## Support

For operator-side documentation, see the **[Operator Guide](./operator-guide.md)**.
