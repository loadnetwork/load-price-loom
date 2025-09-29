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

Recommended checks before using `answer` on‑chain:
- Age bound: `block.timestamp - updatedAt <= MAX_DELAY`.
- Freshness: `roundId == answeredInRound`.
- Optional policy checks: `answer != 0`, within protocol bounds, etc.

If you prefer a single call, you can use `isStale(feedId, maxStalenessSec)` as a convenience, but AggregatorV3‑style checks above remain the most portable.

## Operator Ergonomics (Off‑chain)
When preparing submissions off‑chain:
- Determine the round to sign for: `nextRoundId(feedId)`.
- Check if a new round should start for your proposed price: `dueToStart(feedId, proposed)`.
- Sign the EIP‑712 `PriceSubmission` typed data: `(feedId, roundId, answer, validUntil)`.

## Adapters
The `PriceLoomAggregatorV3Adapter` exposes an AggregatorV3‑compatible surface for a single `feedId`.
- Before first data, it reverts with `"No data present"` to match Chainlink behavior.
- All the freshness and staleness patterns above apply equally via the adapter.

