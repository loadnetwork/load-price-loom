# Oracle Maintenance Guide

This guide covers safe, predictable maintenance operations for Price Loom Oracle: changing operator sets and feed configs, handling stuck rounds, and deploying deterministic adapters.

## Quick Reference: Common Operations

### Add Operator to Feed

```bash
# Set environment
export RPC_URL=http://127.0.0.1:8545
export ORACLE=0x5FbDB2315678afecb367f032d93F642f64180aa3
export FEED=$(cast keccak "ar/bytes-testv1")
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Add operator
cast send $ORACLE "addOperator(bytes32,address)" $FEED 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

**Expected Output:**
```
blockNumber         12345
status              1 (success)
transactionHash     0xabc...
```

### Pause Oracle

```bash
# Pause submissions
cast send $ORACLE "pause()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

**Expected Output:**
```
✅ Oracle paused - no new submissions accepted
```

### Force Close Stuck Round

```bash
# Close timed-out round (works even while paused)
cast send $ORACLE "poke(bytes32)" $FEED --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

**Expected Output:**
```
✅ Round finalized or rolled forward
```

### Unpause Oracle

```bash
# Resume normal operations
cast send $ORACLE "unpause()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

**Expected Output:**
```
✅ Oracle unpaused - submissions resumed
```

### Verify Feed Status

```bash
# Check latest round data
cast call $ORACLE "latestRoundData(bytes32)" $FEED --rpc-url $RPC_URL

# Check if feed is stale (max 3600 seconds)
cast call $ORACLE "isStale(bytes32,uint256)" $FEED 3600 --rpc-url $RPC_URL
```

**Expected Output:**
```
# latestRoundData returns: (roundId, answer, startedAt, updatedAt, answeredInRound)
0x0000000000000000000000000000000000000000000000000000000000000005  # roundId
0x000000000000000000000000000000000000000000000000000000024f05df90  # answer
0x0000000000000000000000000000000000000000000000000000000065a1b2c3  # startedAt
0x0000000000000000000000000000000000000000000000000000000065a1b2c8  # updatedAt
0x0000000000000000000000000000000000000000000000000000000000000005  # answeredInRound

# isStale returns: false (0x0000...0000) if fresh, true (0x0000...0001) if stale
```

---

## Principles
- Admin mutations (add/remove operators, setFeedConfig) are prevented only while a round is open for that feed. This avoids bitmap/index drift and mid‑round DoS.
- `poke(feedId)` is callable while paused. This lets you pause submissions, close any timed‑out open round, then apply admin changes.
- First‑round timeout preserves NoData(): if the very first round times out below quorum, it does not publish a zero; it leaves the feed without data.

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
   - **⚠️ Decimals are immutable** after feed creation and cannot be changed
   - To change decimals, you must create a new feed with a different description and deploy a new adapter
   - Validation enforces bounds, gating, and quorum vs operator count
4) Unpause: `unpause()`

**Important**: If you need to change decimals for an existing feed:
- Create a new feed with a new description (e.g., `"AR/byte:v2"`)
- Configure the new feed with desired decimals
- Deploy a new adapter for the new feed
- Migrate consumers to use the new adapter address
- Consider running both feeds in parallel during migration

### Close a Stuck Round

If a round has fewer than `minSubmissions` and operators are offline:
1. Wait until `timeoutSec` from `startedAt`.
2. Call `poke(feedId)` to either finalize (if ≥ min) or roll forward stale (if < min). `poke` works while paused.

**Automated Recovery:** The operator bot (`scripts/bot/operators-bot.mjs`) includes automatic recovery logic:
- Tracks consecutive failed ticks (0 successful submissions)
- After 2 failed ticks, automatically calls `poke(feedId)` to force timeout handling
- Resumes normal operation once state is recovered

This eliminates the need for manual intervention in most stuck-round scenarios.

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
- `getLatestPrice(feedId)` and `latestRoundData(feedId)` revert with `NoData()` until the first finalize.
- `getRoundData(feedId, roundId)` reverts with `HistoryEvicted()` if outside the 128‑round history window.
- `latestFinalizedRoundId(feedId)` returns the last finalized round id.
- `RoundStarted`, `RoundFinalized`, and `PriceUpdated` events describe lifecycle transitions.

### Stale Roll‑Forward Semantics (DeFi‑compatible)
- When a round times out below quorum and the oracle rolls forward the previous answer, the oracle:
  - Marks the snapshot as `stale = true`.
  - Preserves `answeredInRound` from the last finalized round (so `answeredInRound < roundId`).
  - Preserves the previous `updatedAt` timestamp (does NOT set it to `block.timestamp`).
- This mirrors common AggregatorV3 consumer patterns:
  - Age checks like `block.timestamp - updatedAt <= MAX_DELAY` will treat rolled‑forward prices as stale.
  - Freshness checks like `roundId == answeredInRound` will fail for rolled‑forward prices.
- A convenience view `isStale(feedId, maxStalenessSec)` returns true if there is no data yet, if the snapshot is explicitly marked stale, or if `updatedAt` exceeds the max staleness window.

## Monitoring & Testing

### Integration Testing

After any maintenance operation, verify the full stack works:

```bash
# Test oracle → adapter → consumer integration
node scripts/test-adapter-consumer.mjs
```

This verifies:
- Oracle returns latest round data
- Adapter provides Chainlink-compatible interface
- Consumer can read through adapter
- Historical data is accessible

### Operator Bot Health

Monitor the operator bot for:
- **Submission success rate**: Should be >80% (some failures due to race conditions are normal)
- **Consecutive failures**: Alert if >2 (bot will attempt `poke()` recovery)
- **Round progression**: Verify rounds advance every ~heartbeat interval
- **Price staleness**: Check `age` in bot logs (should be <heartbeat * 2)

See bot logs for real-time status:
```
📤 Starting new round 25 for ar/bytes-testv1
  ✍️  0xf39F…2266 → 9923000000  ✅
  ✍️  0x7099…79C8 → 9958000010  ✅
  ✍️  0x3C44…93BC → 9981000020  ✅
  📊 3/6 operators submitted successfully
🟢 latest round=25 answer=9981000020 age=1s changed=🔄
```

## Best Practices
- Plan operator/config changes: pause → poke (if needed) → change → unpause.
- Keep `minSubmissions ≤ maxSubmissions ≤ operatorCount`.
- Use deterministic adapters in environments where stable addresses matter.
- Run integration tests after any config change.
- Monitor operator bot logs for submission health and recovery events.
- Test pause/unpause and recovery procedures on testnet before mainnet.

---

## Related Documentation

- **[Deployment Cookbook](./deployment-cookbook.md)** - Initial deployment and configuration
- **[Operator Guide](./operator-guide.md)** - Operator node setup and management
- **[Scripts & Bots](../scripts/README.md)** - Integration testing and operator bot
- **[Local Development Guide](./local-development-guide.md)** - Test maintenance procedures locally
- **[Oracle Design](./oracle-design-v0.md)** - Architecture and technical specification
