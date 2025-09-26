# Price Loom Oracle v0 Design

## Overview
- Push-based, multi-feed price oracle with on-chain aggregation.
- Operators submit prices either directly (tx) or via EIP-712 signatures; contract medianizes per round.
- Freshness via heartbeat and deviation triggers; liveness via timeout and a public poke.
- Public reads, plus Chainlink-compatible views via a per-feed adapter.

## Key Defaults
- Operators per feed: 5 (quorum 3, max 5).
- Aggregation: median. For even counts, average the two middle values (round half up).
- Decimals: 18 (answers expressed in AR per byte at 1e18 scale).
- Winston conversion off-chain: `answer_18 = winston_per_byte * 1e6` (since `1 AR = 1e12 winston`).
- Round gating: new round when `heartbeatSec` elapsed or `deviationBps` exceeded.
- Finalization: when `maxSubmissions` reached or `timeoutSec` elapsed with `submissionCount ≥ minSubmissions`.

## Contracts
- `Oracle` (upgradeable; OpenZeppelin AccessControl, Pausable, EIP712, ReentrancyGuard).
- `FeedAdapter` (optional, per feed) implements Chainlink `AggregatorV3Interface` and delegates reads to `Oracle`.

## Roles
- `DEFAULT_ADMIN_ROLE`: multisig (upgrade, config, operator admin).
- `PAUSER_ROLE`: multisig (pause/unpause writes).
- `FEED_ADMIN_ROLE`: multisig (per-feed config/ops).
- `OPERATOR_ROLE[feedId]`: per-feed operator allowlist (internal mapping from address to index).

## Data Model
```solidity
struct FeedConfig {
    uint8  decimals;       // default 18
    uint8  minSubmissions; // default 3
    uint8  maxSubmissions; // default 5
    uint8  trim;           // default 0; reserved for future trimmed mean
    uint32 heartbeatSec;
    uint32 deviationBps;   // e.g., 50 = 0.5%
    uint32 timeoutSec;
    int256 minPrice;       // inclusive, scaled by `decimals`
    int256 maxPrice;       // inclusive, scaled by `decimals`
    string description;    // human label, e.g., "AR/byte"
}

struct RoundData {
    uint80  roundId;
    int256  answer;
    uint256 startedAt;
    uint256 updatedAt;
    uint80  answeredInRound;
    bool    finalized;
    bool    stale;
    uint8   submissionCount;
}

struct FeedState {
    uint80   latestRoundId;
    int256   latestAnswer;
    uint256  latestTimestamp;
    address[] operators; // index used in bitmap
}
```
Working state per open round:
- `submittedBitmap[feedId][roundId] -> uint256` (operator index bitset; supports up to 256 operators, v0 uses 5).
- `answers[feedId][roundId] -> int256[MAX_OPERATORS]` (fixed-size buffer; only first `submissionCount` entries used).
- `answerCount[feedId][roundId] -> uint8`.

Notes:
- Recommend `MAX_OPERATORS = 31` to keep a single `uint256` bitmap well within bounds; v0 uses 5.
- Store finalized `RoundData` snapshots; keep working arrays only for current round.

## Feed Identity
- Each feed is keyed by `bytes32 feedId` (e.g., `keccak256("AR/byte")`).
- Per-feed configs, operators, and rounds are isolated; cross-feed mixing reverts.
- If description changes, create a new feed (do not mutate feedId derived from description).

## Interfaces (Multi-Feed)
```solidity
function getLatestPrice(bytes32 feedId) external view returns (int256 price, uint256 updatedAt);
function latestRoundData(bytes32 feedId) external view returns (
    uint80 roundId,
    int256 answer,
    uint256 startedAt,
    uint256 updatedAt,
    uint80 answeredInRound
);
function getRoundData(bytes32 feedId, uint80 roundId) external view returns (
    uint80 roundId,
    int256 answer,
    uint256 startedAt,
    uint256 updatedAt,
    uint80 answeredInRound
);
function getConfig(bytes32 feedId) external view returns (FeedConfig memory);
function isOperator(bytes32 feedId, address op) external view returns (bool);
function currentRoundId(bytes32 feedId) external view returns (uint80);
function isStale(bytes32 feedId, uint256 maxStalenessSec) external view returns (bool);
```

Adapter (optional, per feed) exposes standard Chainlink `AggregatorV3Interface` by delegating to `Oracle`.

## Write APIs
- EIP-712 signatures (v0, permissionless submit; operator signs, anyone submits):
```solidity
struct PriceSubmission {
    bytes32 feedId;
    uint80  roundId;
    int256  answer;
    uint256 validUntil;
}
function submitSigned(bytes32 feedId, PriceSubmission calldata sub, bytes calldata sig) external whenNotPaused;
function submitSignedBatch(bytes32 feedId, PriceSubmission[] calldata subs, bytes[] calldata sigs) external whenNotPaused;
```

Admin:
```solidity
function createFeed(bytes32 feedId, FeedConfig calldata cfg, address[] calldata operators) external;
function setFeedConfig(bytes32 feedId, FeedConfig calldata cfg) external;
function addOperator(bytes32 feedId, address op) external;
function removeOperator(bytes32 feedId, address op) external;
function pause() external; function unpause() external;
```

Maintenance:
```solidity
function poke(bytes32 feedId) external; // finalize timed-out round or roll forward
```

## EIP-712 Details
- Domain:
  - `name = "Price Loom"`
  - `version = "1"`
  - `chainId = block.chainid`
  - `verifyingContract = address(this)`
- Typehash:
  - `PRICE_SUBMISSION_TYPEHASH = keccak256("PriceSubmission(bytes32 feedId,uint80 roundId,int256 answer,uint256 validUntil)")`
- Digest:
  - `bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(TYPEHASH, feedId, roundId, answer, validUntil)));`
- Verify per item:
  - `address signer = ECDSA.recover(digest, sig);`
  - Require `signer` is operator for `feedId` and hasn’t submitted this round.
  - Require `block.timestamp <= validUntil`.
  - Require `sub.feedId == feedId` and `sub.roundId == currentRound(feedId)`.

Replay protection:
- Include `feedId`, `roundId`, domain fields.
- Dedupe by `(feedId, roundId, signer)` via bitmap.
- `validUntil` prevents acceptance of stale quotes.

Operator flow:
- Off-chain service fetches `currentRoundId(feedId)` and signs `{feedId, roundId, answer, validUntil}`.
- Any relayer submits one or many signatures for that round.
- Mixed `feedId` or `roundId` in a batch reverts.

## Round Lifecycle
Definitions:
- A round is open when it has `roundId = latestRoundId + 1` and is not finalized.
- Start a new round if either heartbeat elapsed or deviation exceeded relative to `latestAnswer`.

Submit path:
1. On first valid submission after `shouldStartNewRound(answer)`, open `roundId = latestRoundId + 1`, set `startedAt = now`.
2. For each valid submission:
   - Check price within `[minPrice, maxPrice]`.
   - Ensure signer/operator hasn’t submitted in this round (bitmap).
   - Record answer; increment count; emit `SubmissionReceived`.
3. If `submissionCount == maxSubmissions`, finalize immediately.

Timeout path:
- If `timeoutSec` elapsed since `startedAt`:
  - If `submissionCount ≥ minSubmissions`, finalize with current set.
  - Else, carry forward previous `latestAnswer`, set `stale = true`, increment `latestRoundId`.

Finalization:
- Sort the `submissionCount` answers (small fixed array; insertion sort).
- If odd → choose median element.
- If even → average the two middle values; round half up.
- Update `latestAnswer`, `latestTimestamp = now`, `answeredInRound = roundId`, set `finalized = true`, `stale = false`.
- Emit `RoundFinalized` and `PriceUpdated`.
- Store finalized snapshot into ring buffer (capacity 128). Older rounds are evicted.

Edge cases:
- First round: allow heartbeat path even if `latestAnswer` is unset (ignore deviation until first finalized).
- Deviation calc uses `max(|latestAnswer|, 1)` to avoid division by zero.
- Negative answers are allowed by type but typically disallowed via `minPrice >= 0` (recommended for AR/byte).

## Guardrails
- Per-feed operator sets and bitmaps prevent cross-feed mixing and double-submits.
- Bounds checks reject outliers.
- Pausable writes; reads remain available with a staleness flag.
- `validUntil` per submission avoids late acceptance.
- Decimals are immutable per feed after creation.

## Events
```solidity
event FeedCreated(bytes32 indexed feedId, FeedConfig cfg);
event FeedConfigUpdated(bytes32 indexed feedId, FeedConfig cfg);
event OperatorAdded(bytes32 indexed feedId, address op);
event OperatorRemoved(bytes32 indexed feedId, address op);
event SubmissionReceived(bytes32 indexed feedId, uint80 indexed roundId, address operator, int256 answer);
event RoundFinalized(bytes32 indexed feedId, uint80 indexed roundId, uint8 submissionCount);
event PriceUpdated(bytes32 indexed feedId, int256 answer, uint256 updatedAt);
event Paused(address account);
event Unpaused(address account);
```

## Security Considerations
- Access control via OZ `AccessControl`; admin is a multisig.
- Guard write paths with `nonReentrant`.
- Use OZ `ECDSA` to avoid signature malleability.
- Prefer Transparent or UUPS proxy; preserve storage layout and include storage gaps.
- Reorg tolerance: rely on finalized blocks; record `updatedAt = block.timestamp`.

## Gas Notes (rough)
- ECDSA verify ~20–25k gas/signature; batch of 5 adds ~100–125k plus oracle logic.
- Sorting up to 5 values is trivial (<10k).
- Bitmap checks are O(1).
- Batch submit amortizes calldata and base transaction costs.

## Admin Ops
- Configure per-feed `heartbeatSec`, `deviationBps`, `timeoutSec`, bounds, decimals.
- Add/remove operators with events; require `operators.length ≤ MAX_OPERATORS`.
- Update description by creating a new feed (do not mutate `feedId`).

## Testing Plan
- Median/average correctness for N = 1..5 with negatives and bounds edges.
- Heartbeat/deviation gating and round start rules.
- Timeout finalize and stale carry-forward with 0/1 submission.
- Bitmap dedupe and operator removal mid-round.
- Bounds enforcement and pause behavior.
- Signature verification:
  - Valid signature accepted; wrong `feedId`/`roundId`/expired rejected.
  - Mixed `feedId` or `roundId` in batch reverts.
  - Duplicate signer in batch rejected.
- Fuzz tests:
  - Random answer sets within bounds → deterministic median.
  - Deviation math across small/large magnitudes.
- Adapter tests: `FeedAdapter` mirrors `latestRoundData` and `decimals/description/version`.
- History tests: after >128 rounds, oldest rounds revert via `HIST_EVICTED`; recent rounds read correctly.

## Migration / Integration
- Consumers read via `getLatestPrice(feedId)` or `latestRoundData(feedId)`.
- For Chainlink-only consumers, deploy a `FeedAdapter(feedId, oracle)` per feed.
- Consumers should check freshness using `updatedAt` and/or a local `maxStalenessSec`.
- Historical reads are bounded to the last 128 rounds; older round queries revert.

## Future Extensions
- Threshold “single price” signatures to finalize immediately (off-chain coordination on the same answer).
- Per-feed fee model for submissions or relayer rebates.
- Consumer gating or payment models if needed.
- Multi-asset batch submissions to reduce gas across feeds.
- Optional on-chain TWAP per feed.
