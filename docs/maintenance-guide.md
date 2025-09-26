# Oracle Maintenance Guide

This guide covers safe, predictable maintenance operations for Price Loom Oracle: changing operator sets and feed configs, handling stuck rounds, and deploying deterministic adapters.

## Principles
- Admin mutations (add/remove operators, setFeedConfig) are prevented only while a round is open for that feed. This avoids bitmap/index drift and mid‑round DoS.
- `poke(feedId)` is callable while paused. This lets you pause submissions, close any timed‑out open round, then apply admin changes.
- First‑round timeout preserves NO_DATA: if the very first round times out below quorum, it does not publish a zero; it leaves the feed without data.

## Operational Modes
- Incident freeze: pause the contract and do not call `poke`. State will not progress while paused and un‑poked.
- Maintenance during pause: if you want liveness (e.g., roll stale and keep adapters current), call `poke(feedId)` as needed while paused.

## Common Flows

### Change Operator Set (Add/Remove)
1) Pause to prevent a new round from opening while you operate:
   - `pause()` (PAUSER_ROLE)
2) Close any timed‑out open round (if present):
   - `poke(feedId)` (allowed while paused)
3) Apply operator change (FEED_ADMIN_ROLE):
   - `addOperator(feedId, op)` or `removeOperator(feedId, op)`
   - Invariants enforced: resulting operator count must be ≥ `minSubmissions` and ≥ `maxSubmissions`.
4) Unpause to resume submissions:
   - `unpause()`

Notes
- If no round is open, you may skip step 2.
- If a round is open but not timed out yet, you must either wait until timeout or unpause and allow it to close normally before making changes.

### Update Feed Config
1) Pause writes: `pause()`
2) Close timed‑out open round if any: `poke(feedId)`
3) Update config: `setFeedConfig(feedId, cfg)`
   - Decimals are immutable post‑creation.
   - Validation enforces bounds, gating, and quorum vs operator count.
4) Unpause: `unpause()`

### Close a Stuck Round
- If a round has fewer than `minSubmissions` and operators are offline:
  1) Wait until `timeoutSec` from `startedAt`.
  2) Call `poke(feedId)` to either finalize (if ≥ min) or roll forward stale (if < min). `poke` works while paused.

## CLI Examples (cast)

Set env:
```
export RPC=<RPC>
export ORACLE=<oracle_address>
export FEED=$(cast keccak "AR/byte")
```

Pause:
```
cast send $ORACLE "pause()" --rpc-url $RPC --private-key $PK
```

Poke (while paused):
```
cast send $ORACLE "poke(bytes32)" $FEED --rpc-url $RPC --private-key $PK
```

Add operator:
```
cast send $ORACLE "addOperator(bytes32,address)" $FEED 0xOp --rpc-url $RPC --private-key $PK
```

Remove operator:
```
cast send $ORACLE "removeOperator(bytes32,address)" $FEED 0xOp --rpc-url $RPC --private-key $PK
```

Update config:
```
cast send $ORACLE "setFeedConfig(bytes32,(uint8,uint8,uint8,uint8,uint32,uint32,uint32,int256,int256,string))" \
  $FEED \
  "(18,3,5,0,3600,50,900,0,10000000000000000000000,'AR/byte')" \
  --rpc-url $RPC --private-key $PK
```

Unpause:
```
cast send $ORACLE "unpause()" --rpc-url $RPC --private-key $PK
```

## Deterministic Adapter Deployment (CREATE2)

For stable adapter addresses per `feedId`, use the factory’s CREATE2 method.

Solidity:
```solidity
address adapter = factory.deployAdapterDeterministic(feedId);
```

Notes
- Salt = `feedId`. Re-deploying with the same salt reverts.
- You can precompute the address off-chain from the factory address, salt, and init code hash if needed.

On-chain prediction via factory helper (cast):
```
export FACTORY=<factory_address>
cast call $FACTORY "computeAdapterAddress(bytes32)(address)" $FEED --rpc-url $RPC
```

Verify after deployment:
```
cast send $FACTORY "deployAdapterDeterministic(bytes32)" $FEED --rpc-url $RPC --private-key $PK
PRED=$(cast call $FACTORY "computeAdapterAddress(bytes32)(address)" $FEED --rpc-url $RPC)
CODE=$(cast code $PRED --rpc-url $RPC)
echo $CODE # non-empty if deployed
```

## Read Semantics & Helpers
- `getLatestPrice(feedId)` and `latestRoundData(feedId)` revert with `NO_DATA` until the first finalize.
- `getRoundData(feedId, roundId)` reverts with `HIST_EVICTED` if outside the 128‑round history window.
- `latestFinalizedRoundId(feedId)` returns the last finalized round id.
- `RoundStarted`, `RoundFinalized`, and `PriceUpdated` events describe lifecycle transitions.

## Best Practices
- Plan operator/config changes: pause → poke (if needed) → change → unpause.
- Keep `minSubmissions ≤ maxSubmissions ≤ operatorCount`.
- Use deterministic adapters in environments where stable addresses matter.
