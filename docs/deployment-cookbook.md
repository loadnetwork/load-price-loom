# Deployment Cookbook

Scenarios, commands, and copy‑paste snippets for common tasks.

## Quick Start: Complete Local Deployment

### 1. Deploy Everything (One Command)

```bash
# Start Anvil in separate terminal first
anvil

# Then deploy oracle + factory + feeds + adapters
export ADMIN=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
make anvil-bootstrap-all
```

**Expected Output:**
```
✅ Oracle deployed: 0x5FbDB2315678afecb367f032d93F642f64180aa3
✅ Factory deployed: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
✅ Feed created: ar/bytes-testv1 (0x3f32666a...)
✅ Adapter deployed: 0xD9164F568A7d21189F61bd53502BdE277883A0A2
```

### 2. Start Operator Bot

```bash
# Copy oracle address from output above
export ORACLE=0x5FbDB2315678afecb367f032d93F642f64180aa3
node scripts/bot/operators-bot.mjs \
  --rpc http://127.0.0.1:8545 \
  --oracle $ORACLE \
  --feedDesc "ar/bytes-testv1" \
  --interval 30000
```

**Expected Output:**
```
🚀 Operator bot starting
✅ Initialized 6/6 valid operator wallets
📤 Starting new round 1 for ar/bytes-testv1
  ✍️  0xf39F…2266 → 9923000000  ✅
  ✍️  0x7099…79C8 → 9958000010  ✅
  ✍️  0x3C44…93BC → 9981000020  ✅
  ✅ Quorum (3) reached—skipping remaining operators
🟢 latest round=1 answer=9981000020 age=1s changed=🔄
```

### 3. Test Integration

```bash
# Deploy test consumer (copy adapter address from step 1)
export ADAPTER=0xD9164F568A7d21189F61bd53502BdE277883A0A2
forge script script/DeployTestConsumer.s.sol:DeployTestConsumer \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Run integration test (copy consumer address from output)
export CONSUMER=0x610178dA211FEF7D417bC0e6FeD39F05609AD788
node scripts/test-adapter-consumer.mjs
```

**Expected Output:**
```
🧪 Testing Adapter & Consumer Integration
📊 Testing Oracle...
  ✅ Latest Round Data: Round ID: 2, Answer: 9992000030
🔌 Testing Adapter (Chainlink-compatible)...
  ✅ Adapter data matches Oracle
🛒 Testing Consumer Contract...
  ✅ Consumer data matches Oracle & Adapter
✅ ALL TESTS PASSED!
```

---

## Addresses & Feed IDs

### Computing Feed IDs

Feed IDs are `bytes32` values computed as the keccak256 hash of the feed description string:

**Solidity:**
```solidity
bytes32 feedId = keccak256(abi.encodePacked("AR/byte"));
```

**JavaScript/TypeScript (ethers v6):**
```ts
import { ethers } from "ethers";
const feedId = ethers.id("AR/byte");  // id() === keccak256(toUtf8Bytes())
```

**Command line (cast):**
```bash
export FEED_ID=$(cast keccak "AR/byte")
```

**Note**: The feed description is case-sensitive. `"AR/byte"` and `"ar/byte"` produce different feed IDs.

### Predicting Adapter Addresses

For deterministic CREATE2 deployments, predict adapter addresses via factory:
```bash
cast call $FACTORY "computeAdapterAddress(bytes32)" $FEED_ID --rpc-url $RPC_URL
```

## New Oracle + Factory + Feeds + Adapters (One Shot)
```bash
export ADMIN=0xAdmin
# Alphanet shortcut
make alphanet-bootstrap-all
# or local Anvil
make anvil-bootstrap-all FEEDS_FILE=feeds-anvil.json
```

## Modular Flow (Production)

Use this step-by-step approach for production deployments to verify each stage.

### Step 1: Deploy Oracle

```bash
# Deploy PriceLoomOracle with secure admin address (e.g., Multi-Sig)
export ADMIN=0xYourMultiSigAddress
forge create src/PriceLoomOracle.sol:PriceLoomOracle \
  --rpc-url https://alphanet.load.network \
  --constructor-args $ADMIN \
  --private-key $DEPLOYER_PRIVATE_KEY
```

**Expected Output:**
```
Deployer: 0x123...
Deployed to: 0x5FbDB2315678afecb367f032d93F642f64180aa3
Transaction hash: 0xabc...
```

### Step 2: Deploy Factory

```bash
# Copy oracle address from Step 1
export ORACLE=0x5FbDB2315678afecb367f032d93F642f64180aa3
make alphanet-deploy-factory
```

**Expected Output:**
```
✅ Factory deployed: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
   Bound to oracle: 0x5FbDB2315678afecb367f032d93F642f64180aa3
```

### Step 3: Create Feeds from JSON

```bash
# Ensure feeds.json is configured with your feed parameters
export ORACLE=0x5FbDB2315678afecb367f032d93F642f64180aa3
make alphanet-create-feeds-json FEEDS_FILE=feeds.json
```

**Expected Output:**
```
Creating feeds from feeds.json...
✅ Feed created: AR/byte (feedId: 0x3f32...)
✅ Feed created: ETH/USD (feedId: 0x7a21...)
✅ 2 feeds created successfully
```

### Step 4: Deploy Adapters

```bash
# Copy factory address from Step 2
export FACTORY=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
make alphanet-deploy-adapters-json FEEDS_FILE=feeds.json
```

**Expected Output:**
```
Deploying adapters from feeds.json...
✅ Adapter deployed: AR/byte → 0xD916...
✅ Adapter deployed: ETH/USD → 0x8A3C...
✅ 2 adapters deployed successfully
```

### Step 5: Verify Deployment

```bash
# Check oracle has feeds
cast call $ORACLE "getConfig(bytes32)" $(cast keccak "AR/byte") --rpc-url https://alphanet.load.network

# Check adapter points to correct oracle
export ADAPTER=0xD9164F568A7d21189F61bd53502BdE277883A0A2
cast call $ADAPTER "decimals()" --rpc-url https://alphanet.load.network
```

**Expected Output:**
```
# getConfig returns tuple with decimals, min/max submissions, etc.
# decimals() returns: 8 (or your configured decimals)
```

## Create One Feed (Env‑Driven)

```bash
# Set all feed parameters via environment variables
export ORACLE=0x5FbDB2315678afecb367f032d93F642f64180aa3
export FEED_DESC="AR/byte"
export DECIMALS=8
export MIN_SUBMISSIONS=2
export MAX_SUBMISSIONS=3
export HEARTBEAT_SEC=3600
export DEVIATION_BPS=50
export TIMEOUT_SEC=900
export MIN_PRICE=0
export MAX_PRICE=10000000000000000000000
export DESCRIPTION="AR/byte price feed"
export OPERATORS_JSON='["0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","0x70997970C51812dc3A010C7d01b50e0d17dc79C8","0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"]'

# Create feed
make alphanet-create-feed-env
```

**Expected Output:**
```
Creating feed AR/byte...
  feedId: 0x3f32666a3e43d4d82c6c5b5e89e2d0b8c8fb4c8a9c20b7b0d8c6e8f8a4b2c6d8
  decimals: 8
  operators: 3
✅ Feed created successfully
```

## Pause, Poke, Config Changes

### Pause Submissions

```bash
export ORACLE=0x5FbDB2315678afecb367f032d93F642f64180aa3
export RPC_URL=https://alphanet.load.network
export PRIVATE_KEY=0xYourPrivateKey

cast send $ORACLE "pause()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

**Expected Output:**
```
status              1 (success)
✅ Oracle paused
```

### Poke Feeds (Force Close Timed-Out Rounds)

```bash
# Poke single feed
export FEED_ID=$(cast keccak "AR/byte")
cast send $ORACLE "poke(bytes32)" $FEED_ID --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Or poke all feeds from JSON (works while paused)
make alphanet-poke-feeds-json ORACLE=$ORACLE FEEDS_FILE=feeds.json
```

**Expected Output:**
```
✅ Round 25 finalized for AR/byte
✅ Round 18 rolled forward (stale) for ETH/USD
```

### Update Feed Config

```bash
# Ensure no open round before updating config
export FEED_ID=$(cast keccak "AR/byte")

# Update config (example: change heartbeat to 7200 seconds)
cast send $ORACLE "setFeedConfig(bytes32,(uint8,uint8,uint8,uint8,uint32,uint32,uint32,int256,int256,string))" \
  $FEED_ID "(8,2,3,0,7200,50,900,0,10000000000000000000000,'AR/byte updated')" \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

**Expected Output:**
```
status              1 (success)
✅ Feed config updated
```

## Add/Remove Operators

### Add Operator

```bash
export FEED_ID=$(cast keccak "AR/byte")
export NEW_OPERATOR=0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc

cast send $ORACLE "addOperator(bytes32,address)" $FEED_ID $NEW_OPERATOR \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

**Expected Output:**
```
status              1 (success)
✅ Operator 0x9965...A4dc added to feed AR/byte
```

### Remove Operator

```bash
export OLD_OPERATOR=0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc

cast send $ORACLE "removeOperator(bytes32,address)" $FEED_ID $OLD_OPERATOR \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

**Expected Output:**
```
status              1 (success)
✅ Operator 0x9965...A4dc removed from feed AR/byte
```

### Verify Operators

```bash
# List all operators for a feed
cast call $ORACLE "getOperators(bytes32)" $FEED_ID --rpc-url $RPC_URL
```

**Expected Output:**
```
[0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 0x70997970C51812dc3A010C7d01b50e0d17dc79C8, 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC]
```

## Consumer Freshness (Solidity)
```solidity
(uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = oracle.latestRoundData(feedId);
require(roundId == answeredInRound, "stale-forwarded");
require(block.timestamp - updatedAt <= MAX_DELAY, "stale-age");
```

## Off‑Chain Signing & Operator Bot

### Test Operator Bot (Local Anvil)

After deploying oracle and feeds, run the operator bot to start submitting prices:

```bash
# Install dependencies
npm install

# Run bot with deployed addresses
node scripts/bot/operators-bot.mjs \
  --rpc http://127.0.0.1:8545 \
  --oracle $ORACLE \
  --feedDesc "ar/bytes-testv1" \
  --interval 30000
```

The bot will:
- Automatically match on-chain operators with Anvil test keys
- Submit prices sequentially (minSubmissions reached, then stop)
- Recover automatically from stuck rounds via `poke()`
- Handle pause/unpause gracefully

See `docs/operator-guide.md` for production setup and `docs/operator-bot-fix-report.md` for architecture details.

### Integration Testing

Verify the full stack (oracle → adapter → consumer):

```bash
# Deploy test consumer
export ADAPTER=0xAdapterAddress
forge script script/DeployTestConsumer.s.sol:DeployTestConsumer \
  --rpc-url $RPC_URL --broadcast --sender $ADMIN

# Test integration
export CONSUMER=0xConsumerAddress
node scripts/test-adapter-consumer.mjs
```

This tests:
- Oracle latest round data
- Adapter Chainlink compatibility
- Consumer reads through adapter
- Historical data access

## Network Safety & Diagnostics
- Use `anvil-<target>` or `alphanet-<target>` prefixed make targets to auto-set RPC_URL and CHAIN_ID.
- `make doctor` prints the selected RPC/CHAIN_ID and the live chain-id from the RPC.
- All script targets verify the remote chain-id before broadcasting and pass `--chain-id` to sign with the correct domain.

---

## Related Documentation

- **[Local Development Guide](./local-development-guide.md)** - Test deployments locally with Anvil
- **[Maintenance Guide](./maintenance-guide.md)** - Post-deployment operations
- **[Operator Guide](./operator-guide.md)** - Run operator nodes after deployment
- **[Scripts & Bots](../scripts/README.md)** - Operator bot and integration testing
- **[Pre-Mainnet Checklist](./pre-mainnet-checklist.md)** - Production readiness requirements
