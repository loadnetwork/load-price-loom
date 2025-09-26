# Oracle Implementation Overview (v0)

This document explains how the current oracle scaffolding works: what each function, data structure, and event does, and how they connect.

## High‑Level Flow
- Operators push prices per `feedId` using EIP‑712 signatures (`submitSigned`/`submitSignedBatch`).
- The contract opens a new round when heartbeat/deviation rules say it’s due.
- Each operator may submit once per round; answers are deduped via a bitmap.
- When finalization criteria hit, the round median is computed and published.
- Readers fetch `getLatestPrice` or `latestRoundData`. `getLatestPrice` reverts with `"NO_DATA"` until the first finalize.

## Core Types
- FeedConfig (per‑feed parameters)
  - `decimals`: answer scale (default 18).
  - `minSubmissions`: quorum to finalize on timeout (default 3).
  - `maxSubmissions`: max operators per round (default 5).
  - `trim`: reserved for future trimmed mean (0 in v0).
  - `heartbeatSec`: max time between updates before forcing a new round.
  - `deviationBps`: basis‑point threshold to start a new round early.
  - `timeoutSec`: time after first submission to allow finalize/roll.
  - `minPrice`, `maxPrice`: per‑feed bounds in `decimals` units.
  - `description`: human label, e.g., "AR/byte".
- RoundData (latest finalized snapshot)
  - `roundId`, `answer`, `startedAt`, `updatedAt`, `answeredInRound`.
  - `finalized`: always true for the snapshot; indicates finalized state.
  - `stale`: whether value is considered stale (used on carry‑forward).
  - `submissionCount`: number of answers used to produce the snapshot.

## Storage Layout (per feed)
- `_feedConfig[feedId]` → `FeedConfig`.
- `_operators[feedId]` → `address[]` ordered list; 1‑based index.
- `_opIndex[feedId][op]` → `uint8` 1‑based index (0 = not operator).
- `_latestSnapshot[feedId]` → latest finalized `RoundData`.
- `_latestRoundId[feedId]` → `uint80` of last finalized round.
- `_roundStartedAt[feedId][roundId]` → start time of open round.
- Open‑round working state (per feed, per round):
  - `_submittedBitmap[feedId][roundId]` → `uint256` bitset for dedupe.
  - `_answers[feedId][roundId][i]` → compact buffer of answers (signed `int256`).
  - `_answerCount[feedId][roundId]` → count of collected answers.

### Bounded History (Ring Buffer)
- `_history[feedId][idx]` → `RoundData` ring buffer slot.
- Capacity = 128 rounds per feed. Index: `idx = (roundId - 1) & 127`.
- Overwrite detection: stored `RoundData.roundId` must equal the requested `roundId`.
- Rationale: provide recent historical reads without unbounded storage.

## Roles & Access
- `DEFAULT_ADMIN_ROLE`: full admin (multisig recommended).
- `FEED_ADMIN_ROLE`: manage feeds/config/operators.
- `PAUSER_ROLE`: pause/unpause submissions (reads continue).
- Submission access: only whitelisted operators per feed (`onlyFeedOperator(feedId)`).

## Read Interfaces (IOracleReader)
- `getLatestPrice(feedId) -> (answer, updatedAt)`: simple consumption.
- `latestRoundData(feedId) -> (roundId, answer, startedAt, updatedAt, answeredInRound)`: Chainlink‑style tuple.
- `getRoundData(feedId, roundId) -> (roundId, answer, startedAt, updatedAt, answeredInRound)`:
  - Reverts with `"bad roundId"` if `roundId == 0`.
  - Reverts with `"HIST_EVICTED"` if the requested round is older than the 128‑round window or not present.
- `getConfig(feedId) -> FeedConfig`: current parameters.
- `isOperator(feedId, op) -> bool`: membership check.
- `currentRoundId(feedId) -> uint80`: returns open round id if started, else last finalized.
- `latestFinalizedRoundId(feedId) -> uint80`: returns last finalized round id.
- `isStale(feedId, maxStalenessSec) -> bool`: consumer freshness helper.

## Admin Interfaces (IOracleAdmin)
- `createFeed(feedId, cfg, operators)`: initialize per‑feed config and operator set; creates empty snapshot (stale=true).
- `setFeedConfig(feedId, cfg)`: update parameters after validation.
- `addOperator(feedId, op)` / `removeOperator(feedId, op)`: modify operator set with index bookkeeping.
- `pause()` / `unpause()`: control write availability.

## Submission Flow (EIP‑712 signed submissions)
- Preconditions
  - Signature signer is an operator for the feed.
  - `validUntil` not expired.
  - `answer` within `[minPrice, maxPrice]` (signed `int256`).
- Round gating
  - If no open round: allow opening if first‑ever update or `_shouldStartNewRound(feedId, answer)` is true (heartbeat elapsed OR deviation exceeded vs latest answer).
  - Mark round start time on the first submission of a new round.
- Deduping
  - `_submittedBitmap` uses a bit per operator index; reverts on duplicate submission within the same round.
- Record answer
  - Store into `_answers[...]` at current count; increment `_answerCount`.
- Finalization trigger
  - If `_answerCount == maxSubmissions` (5), call `_finalizeRound` immediately.

## Finalization (Medianization & Publish)
- Copy the collected `n` answers (n ≤ 5) to memory and sort with insertion sort.
- Median:
  - Odd `n` → middle element.
  - Even `n` → average of the two middle values using round‑half‑up for non‑negative values.
- Update snapshot (`_latestSnapshot[feedId]`):
  - Set `answer`, `roundId`, `startedAt`, `updatedAt`, `answeredInRound`, `submissionCount`, `stale=false`.
  - Set `_latestRoundId[feedId] = roundId`.
- Emit `RoundFinalized` and `PriceUpdated`.
  - On opening a new round, `RoundStarted(feedId, roundId, startedAt)` is emitted.

## Events
- Admin & Ops
  - `FeedCreated(feedId, cfg)`
  - `FeedConfigUpdated(feedId, cfg)`
  - `OperatorAdded(feedId, op)`
  - `OperatorRemoved(feedId, op)`
- Submissions & State
- `SubmissionReceived(feedId, roundId, operator, answer)`
- `RoundFinalized(feedId, roundId, submissionCount)`
- `PriceUpdated(feedId, answer, updatedAt)`
- `RoundStarted(feedId, roundId, startedAt)`
- Pausing (from OZ Pausable)
  - `Paused(account)` / `Unpaused(account)`

## Internal Helpers
- `_withinBounds(feedId, answer)` → min/max guardrail per feed.
- Deviation math uses INT_MIN‑safe absolute value and difference helpers.
- `_heartbeatElapsed(feedId)` → checks `heartbeatSec` vs last `updatedAt`.
- `_exceedsDeviation(feedId, proposed)` → compares absolute diff against `deviationBps` threshold.
- `_shouldStartNewRound(feedId, proposed)` → heartbeat OR deviation.
- `_avgRoundHalfUp(a, b)` → average with round‑half‑up when both non‑negative; otherwise Solidity default (toward zero).
- `_insertionSort(arr, len)` → small‑N sort for median.

## EIP‑712
- Domain: `name = "Price Loom"`, `version = "1"`, chainId = `block.chainid`, verifyingContract = `address(this)`.
- Typehash: `PriceSubmission(bytes32 feedId,uint80 roundId,int256 answer,uint256 validUntil)`.
- Digest: `_hashTypedData(keccak256(abi.encode(TYPEHASH, feedId, roundId, answer, validUntil)))`.
- Functions:
  - `submitSigned(feedId, sub, sig)` and `submitSignedBatch(feedId, subs[], sigs[])`.
  - Anyone can relay signatures; signer must be an operator for the feed.

## Liveness (Next Step)
- `poke(feedId)` and timeout rules finalize with quorum if `timeoutSec` elapsed since round start, or carry forward stale value otherwise. `poke` is allowed while paused to support maintenance.

---

Files of interest:
- `src/oracle/PriceLoomOracle.sol` — contract implementation.
- `src/oracle/PriceLoomTypes.sol` — core types (FeedConfig, RoundData).
- `src/interfaces/IOracleReader.sol` — read API.
- `src/interfaces/IOracleAdmin.sol` — admin API.

## Testing & Next Steps
- Unit tests to add (Foundry):
  - Submit 5 signatures → finalize median; verify events and snapshot.
  - Submit 3 signatures → warp `timeoutSec` → `poke` → finalize at quorum.
  - Submit 2 signatures → warp `timeoutSec` → `poke` → roll forward stale.
  - Bounds, deviation, heartbeat, duplicate signer/bitmap, pause behavior.
- Useful test helpers:
  - EIP‑712 signing utility using `vm.sign` to produce `(v,r,s)` and `sig` bytes.
  - Helper to compute `_hashTypedDataV4` digest that matches on‑chain typehash.

## Chainlink Adapter (What & Why)
- What: a tiny per‑feed wrapper contract that implements `AggregatorV3Interface` and internally calls `PriceLoomOracle.latestRoundData(feedId)`.
- Why: many DeFi apps/tools expect the Chainlink interface (no `feedId` param). The adapter makes the oracle plug‑and‑play for those consumers without changing our multi‑feed core.
- When you need it: only if an integrating dapp/library expects `AggregatorV3Interface` directly. If consumers call `getLatestPrice(feedId)` already, you don’t need the adapter.
- Shape:
  - Constructor stores `feedId` and oracle address.
  - `decimals/description/version` are proxied from oracle config.
  - `latestRoundData()` delegates to `oracle.latestRoundData(feedId)`.
  - `getRoundData(roundId)` delegates to `oracle.getRoundData(feedId, roundId)` and will revert if the round is not available in the 128‑round history.

## No‑Data Semantics
- If a feed has never finalized a round:
  - `latestRoundData(feedId)` reverts with `"NO_DATA"` in the core oracle. The Chainlink adapter normalizes this to `"No data present"` for compatibility.
  - `getLatestPrice(feedId)` also reverts with `"NO_DATA"` until first finalize.
  - `getRoundData(feedId, roundId)` reverts (`"bad roundId"` if `roundId == 0`, or `"HIST_EVICTED"` otherwise). The adapter surfaces `"No data present"` in these cases.
