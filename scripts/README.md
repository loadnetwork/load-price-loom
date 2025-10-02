# Scripts Reference Guide

Quick reference for all JavaScript/Node.js scripts in the repository.

---

## Operator Bot

**Location:** `scripts/bot/operators-bot.mjs`

**Purpose:** Automated price submission bot for testing and local development.

### Quick Start (Copy & Paste)

```bash
# Replace with your deployed oracle address
node scripts/bot/operators-bot.mjs \
  --rpc http://127.0.0.1:8545 \
  --oracle 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
  --feedDesc "ar/bytes-testv1" \
  --interval 30000
```

### Usage

```bash
node scripts/bot/operators-bot.mjs \
  --rpc http://127.0.0.1:8545 \
  --oracle 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
  --feedDesc "ar/bytes-testv1" \
  --interval 30000
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `RPC_URL` | RPC endpoint | `http://127.0.0.1:8545` |
| `ORACLE` | Oracle contract address | Required |
| `FEED_DESC` | Feed identifier string | `ar/bytes-testv1` |
| `FEED_ID` | Alternative: feedId bytes32 | Computed from FEED_DESC |
| `INTERVAL_MS` | Submission interval (ms) | `30000` |
| `NUM_OPS` | Number of operators | `6` |
| `PRIVATE_KEYS_JSON` | Custom operator keys array | Anvil test keys |

### Command Line Arguments

```bash
--rpc <url>           # RPC endpoint
--oracle <address>    # Oracle contract address
--feedDesc <string>   # Feed identifier
--feedId <bytes32>    # Alternative to feedDesc
--interval <ms>       # Submission interval
--ops <number>        # Number of operators
```

### Features

- **Dynamic operator initialization**: Matches on-chain operators with available keys
- **Sequential submissions**: Avoids race conditions by submitting one at a time
- **Automatic recovery**: Calls `poke()` after 2 consecutive failed ticks
- **Pause detection**: Automatically pauses when oracle is paused
- **Comprehensive error handling**: Gracefully handles all oracle error types
- **Real-time logging**: Shows submission status, round progression, price age

### Output Example

```
🚀 Operator bot starting
   rpc=http://127.0.0.1:8545 oracle=0x5FbD…0aa3 feed=ar/bytes-testv1 ops=6 interval=30000ms
✅ Initialized 6/6 valid operator wallets
📤 Starting new round 25 for ar/bytes-testv1
  ✍️  0xf39F…2266 → 9923000000  ✅ 0x4538…b681
  ✍️  0x7099…79C8 → 9958000010  ✅ 0x4d80…fbc0
  ✍️  0x3C44…93BC → 9981000020  ✅ 0xcb85…4de9
  ✅ Quorum (3) reached—skipping remaining operators
  📊 3/6 operators submitted successfully
🟢 latest round=25 answer=9981000020 age=1s changed=🔄
```

### Error Codes

The bot recognizes and handles these oracle errors:

| Error Code | Name | Meaning | Bot Action |
|------------|------|---------|------------|
| `0x32e1428f` | RoundFull | Round has maxSubmissions | Skip gracefully |
| `0x8daa9e49` | DuplicateSubmission | Already submitted this round | Skip gracefully |
| `0xc3fa7054` | WrongRound | Round changed mid-submission | Skip gracefully |
| `0x47a2375f` | NotDue | Heartbeat not met yet | Skip gracefully |
| `0xd93c0665` | EnforcedPause | Oracle is paused | Skip gracefully |
| `0x7c214f04` | NotOperator | Not authorized operator | Error (critical) |

### Production Deployment

**For production use:**
1. Convert to TypeScript for type safety
2. Add structured logging (Winston, Pino)
3. Export metrics (Prometheus format)
4. Add health check endpoint
5. Use KMS for key management (never raw private keys)
6. Deploy with redundancy (multiple bots, different regions)

See [operator-guide.md](./operator-guide.md) for production setup details.

---

## Integration Test Script

**Location:** `scripts/test-adapter-consumer.mjs`

**Purpose:** End-to-end integration testing of oracle → adapter → consumer flow.

### Quick Start (Copy & Paste)

```bash
# Replace with your deployed addresses, then run
export ORACLE=0x5FbDB2315678afecb367f032d93F642f64180aa3
export ADAPTER=0xD9164F568A7d21189F61bd53502BdE277883A0A2
export CONSUMER=0x610178dA211FEF7D417bC0e6FeD39F05609AD788
node scripts/test-adapter-consumer.mjs
```

### Usage

```bash
# Set deployed addresses
export ORACLE=0x5FbDB2315678afecb367f032d93F642f64180aa3
export ADAPTER=0xD9164F568A7d21189F61bd53502BdE277883A0A2
export CONSUMER=0x610178dA211FEF7D417bC0e6FeD39F05609AD788

# Run test
node scripts/test-adapter-consumer.mjs
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `RPC_URL` | RPC endpoint | `http://127.0.0.1:8545` |
| `ORACLE` | Oracle contract address | `0x5FbDB2315678afecb367f032d93F642f64180aa3` |
| `ADAPTER` | Adapter contract address | `0xD9164F568A7d21189F61bd53502BdE277883A0A2` |
| `CONSUMER` | Consumer contract address | `0x610178dA211FEF7D417bC0e6FeD39F05609AD788` |

### What It Tests

1. **Oracle Functionality**
   - Fetches `latestRoundData(feedId)`
   - Reads `getConfig(feedId)` for decimals/description
   - Verifies data is present and valid

2. **Adapter Compatibility**
   - Tests Chainlink `AggregatorV3Interface`
   - Verifies data matches oracle exactly
   - Tests `decimals()`, `description()`, `version()`
   - Tests `latestRoundData()` and `getRoundData(roundId)`

3. **Consumer Integration**
   - Verifies consumer reads from correct adapter
   - Tests consumer's `latest()` function
   - Confirms data consistency across all layers

4. **Historical Data**
   - Fetches previous rounds via oracle and adapter
   - Verifies historical continuity

### Output Example

```
🧪 Testing Adapter & Consumer Integration

Configuration:
  Oracle:   0x5FbD…0aa3
  Adapter:  0xD916…A0A2
  Consumer: 0x6101…D788
  Feed:     ar/bytes-testv1

📊 Testing Oracle...
  ✅ Latest Round Data:
     Round ID:     11
     Answer:       9992000030 (99.9200003)
     Decimals:     8
     Description:  AR/byte test feed
     Age:          20s

🔌 Testing Adapter (Chainlink-compatible)...
  ✅ Latest Round Data:
     Round ID:     11
     Answer:       9992000030
  ✅ Adapter data matches Oracle

🛒 Testing Consumer Contract...
  ✅ Latest Data:
     Answer:       9992000030
  ✅ Consumer data matches Oracle & Adapter

📜 Testing Historical Data Access...
  ✅ Historical data available

═══════════════════════════════════════
✅ ALL TESTS PASSED!
═══════════════════════════════════════
```

### Troubleshooting

**"No data present" error:**
- Ensure operator bot has submitted at least one round
- Check that feed exists in oracle (`getConfig` should not revert)

**"Adapter data mismatch" error:**
- Verify adapter is pointing to correct oracle
- Check that feedId matches

**"Consumer not found" error:**
- Deploy TestPriceConsumer first using Foundry script

---

## Script Workflow

### Complete Local Testing Flow

```bash
# 1. Start local Anvil node (separate terminal)
anvil

# 2. Deploy oracle, factory, and feeds (separate terminal)
export ADMIN=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export ADMIN_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
make anvil-bootstrap-all

# 3. Note deployed addresses from output
export ORACLE=0x5FbDB...
export FACTORY=0xe7f17...
export ADAPTER=0xD916...

# 4. Deploy test consumer
forge script script/DeployTestConsumer.s.sol:DeployTestConsumer \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --sender $ADMIN \
  --private-key $ADMIN_PRIVATE_KEY

export CONSUMER=0x6101...

# 5. Start operator bot (separate terminal)
node scripts/bot/operators-bot.mjs \
  --rpc http://127.0.0.1:8545 \
  --oracle $ORACLE \
  --feedDesc "ar/bytes-testv1" \
  --interval 30000

# 6. Wait for 1-2 rounds to complete (~1 minute)

# 7. Run integration tests
node scripts/test-adapter-consumer.mjs
```

---

## Dependencies

Both scripts require:

```json
{
  "type": "module",
  "dependencies": {
    "ethers": "^6.13.2"
  }
}
```

Install with:
```bash
npm install
```

---

## Related Documentation

- [Operator Guide](../docs/operator-guide.md) - Production operator setup
- [Deployment Cookbook](../docs/deployment-cookbook.md) - Deployment commands and examples
- [Adapter Guide](../docs/adapter-guide.md) - Adapter architecture and usage
- [Maintenance Guide](../docs/maintenance-guide.md) - Operational procedures
- [Operator Bot Fix Report](../docs/operator-bot-fix-report.md) - Detailed bot architecture and troubleshooting

---

## Contributing

When adding new scripts:
1. Use ES modules (`type: "module"` in package.json)
2. Use ethers v6 syntax
3. Support both CLI args and environment variables
4. Add clear usage examples to this document
5. Include error handling for all expected failures
6. Log actions clearly with appropriate emoji/formatting
