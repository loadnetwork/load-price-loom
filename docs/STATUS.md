# Project Status (Price Loom Oracle)

Updated: 2025-09-26

## Summary
- Core oracle implemented (v0): multi‑feed, round‑based medianization with EIP‑712 signed submissions.
- Chainlink AggregatorV3 parity for reads via per‑feed adapter.
- Signed answer type is `int256`; `roundId` is `uint80` across code and EIP‑712.
- Bounded on‑chain history via ring buffer (128 rounds per feed).
- Per‑round working state is cleared after finalize/roll to avoid storage growth.
- Config hardening added; decimals made immutable post‑creation.
 - Maintenance improvements: `poke` callable while paused; admin mutations blocked only when a round is open.

## Decisions
- V3‑only compatibility (no Aggregator v2 interface).
- EIP‑712 domain: name "Price Loom", version "1".
- History capped at 128 rounds; older rounds revert `HIST_EVICTED`.
- `latestRoundData` reverts `NO_DATA` until first finalize.
 - `getLatestPrice` reverts `NO_DATA` until first finalize.

## Completed
- Align types to Chainlink: `int256` answers; `uint80` round ids.
- Update EIP‑712 typehash: `PriceSubmission(bytes32 feedId,uint80 roundId,int256 answer,uint256 validUntil)`.
- Adapter returns signed answers directly; supports historical reads.
- Add ring buffer history and historical getter in oracle.
- Add working‑state cleanup after finalize and stale roll.
- Add config guards: quorum/operator checks; require heartbeat or deviation; decimals immutable.
 - Add `RoundStarted` event and emit on round open.
 - Allow `poke` while paused for clean maintenance flow.
 - Add `latestFinalizedRoundId(feedId)` view.
 - Add deterministic adapter deployment via CREATE2 in factory.
- Docs updated: implementation overview, design v0, adapter guide.

## Next
- Tests (Foundry):
  - First update flow: NO_DATA → finalize → success.
  - Medianization for signed values (odd/even; negative ranges).
  - Timeout finalize vs stale roll; batch dedupe.
  - History window: >128 rounds causes earliest rounds to revert `HIST_EVICTED`.
  - Adapter mirrors oracle results.
- Scripts:
  - Feed creation/config and operator admin scripts.
  - Batch adapter deployment via factory.
- Docs:
  - EIP‑712 client signing snippet (ethers) with the final typehash.
  - Short integration checklist for v3 consumers.

## Open Items / Nice‑to‑Have
- Gas profiling and light audit pass (slither/static checks, invariants where suitable).
 - Add CREATE2 address precompute helper in factory docs or code.
