# Price Loom Oracle

Price Loom is a multi-feed, push-based price oracle for EVM chains. It features EIP-712 signed submissions for gas-efficient updates, on-chain median aggregation, and a Chainlink-compatible adapter for easy integration with the existing DeFi ecosystem.

---

## Documentation

### Getting Started
- **[Local Development Guide](./docs/local-development-guide.md)** - Setup Foundry/Anvil, run tests, debug transactions
- **[Deployment Cookbook](./docs/deployment-cookbook.md)** - Deploy to local/testnet/mainnet with examples

### Integration & Operations
- **[Consumer Guide](./docs/consumer-guide.md)** - How to read prices in your contracts (includes 128-round history limits)
- **[Operator Guide](./docs/operator-guide.md)** - Run a price submission node
- **[Maintenance Guide](./docs/maintenance-guide.md)** - Manage feeds, operators, and configs
- **[Adapter Guide](./docs/adapter-guide.md)** - Chainlink-compatible adapter architecture

### Reference
- **[Scripts & Bots](./scripts/README.md)** - Operator bot and integration testing tools
- **[Oracle Design](./docs/oracle-design-v0.md)** - Architecture and technical specification
- **[Phase Support Roadmap](./docs/phase-support-roadmap.md)** - Future upgrade path for production
- **[Pre-Mainnet Checklist](./docs/pre-mainnet-checklist.md)** - Production readiness requirements

## Quick Start

### Prerequisites
- [Foundry](https://getfoundry.sh/) (forge, cast, anvil)
- [Node.js](https://nodejs.org/) v18+ (for operator bot)
- [Git](https://git-scm.com/)

### Installation

```bash
# Clone repository
git clone <repository-url>
cd load-price-loom

# Install dependencies
git submodule update --init --recursive
forge install
npm install

# Build and test
forge build
forge test
```

### 5-Minute Local Demo

Get a complete oracle system running in 3 terminals:

**Terminal 1: Start Anvil**
```bash
anvil
```

**Terminal 2: Deploy & Run Bot**
```bash
make anvil-bootstrap-all
export ORACLE=0x5FbDB2315678afecb367f032d93F642f64180aa3  # Copy from output

# Run bot for AR/byte feed (18 decimals)
node scripts/bot/operators-bot.mjs \
  --rpc http://127.0.0.1:8545 \
  --oracle $ORACLE \
  --feedDesc "ar/bytes-testv1" \
  --interval 30000 \
  --priceBase 1.5e-9
```

**Terminal 3: Test Integration**
```bash
export ADAPTER=0xD916...  # Copy from Terminal 2
forge script script/DeployTestConsumer.s.sol:DeployTestConsumer \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast

export CONSUMER=0x6101...  # Copy from output
node scripts/test-adapter-consumer.mjs
```

**Expected Result:** `✅ ALL TESTS PASSED!`

📚 **Next Steps:** See the [Local Development Guide](./docs/local-development-guide.md) for detailed workflows, debugging, and Foundry commands.

---

## Production Deployment

For production deployments, see the **[Deployment Cookbook](./docs/deployment-cookbook.md)** which provides:
- Step-by-step deployment commands with expected outputs
- Modular workflow for testnet/mainnet
- Feed and adapter deployment examples
- Verification commands

**Production deployment overview:**
1. Deploy `PriceLoomOracle` with secure admin (Multi-Sig)
2. Deploy `PriceLoomAdapterFactory` bound to oracle
3. Create feeds from `feeds.json` configuration
4. Deploy Chainlink-compatible adapters for each feed
5. Verify deployment and run integration tests

See the [Pre-Mainnet Checklist](./docs/pre-mainnet-checklist.md) before production deployment.

---

## Live Deployments

### Alphanet (Load Network Testnet)

**Network Details:**
- RPC URL: `https://alphanet.load.network`
- Chain ID: `9496`

**Deployed Contracts:**
```
Oracle:  0x8A0ffF4C118767c818C9F8a30c39E8F9bB36CEd5
Factory: 0x1ABCC90656DBAd9429B96A5deA14e5aBBEF6fAd5
```

**Feeds:**
| Feed | Feed ID | Decimals | Adapter |
|------|---------|----------|---------|
| `ar/bytes-testv1` | `0x3f32666a158724369a9dd545820fe3317324bc95cc0955f73607bbfd95fee049` | 18 | `0xCbbbff18714b1276756980BA7691C67052C9C9ff` |
| `ar/usd-testv1` | `0x826dd31c4b24704b320ca6210fa82fb8ebffc7b9c7b4bb36032ec09ac1b137f2` | 8 | `0x920380c14685b88Bb8f6D6A35def83D085152550` |

**Usage Example:**
```solidity
// Import Chainlink interface
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// Use AR/byte adapter
AggregatorV3Interface feed = AggregatorV3Interface(0xCbbbff18714b1276756980BA7691C67052C9C9ff);
(, int256 price, , uint256 updatedAt, ) = feed.latestRoundData();
// price is in 18 decimals: 1.5e-9 AR/byte = 1500000000 (1.5e9)
```

---

## Operations & Maintenance

### For Operators

Run a price submission node to provide reliable price data. See **[Operator Guide](./docs/operator-guide.md)** for:
- Key management and security best practices
- EIP-712 signature construction
- Submission workflow and error handling
- Production monitoring and alerting

**Quick test with operator bot:**
```bash
# AR/byte feed (18 decimals, ~1.5e-9 AR/byte)
node scripts/bot/operators-bot.mjs \
  --rpc https://alphanet.load.network \
  --oracle 0xYourOracleAddress \
  --feedDesc "ar/bytes-testv1" \
  --interval 30000 \
  --priceBase 1.5e-9

# AR/USD feed (8 decimals, ~$6 per AR)
node scripts/bot/operators-bot.mjs \
  --rpc https://alphanet.load.network \
  --oracle 0xYourOracleAddress \
  --feedDesc "ar/usd-testv1" \
  --interval 30000 \
  --priceBase 6
```

### For Maintainers

Manage feeds, operators, and configs. See **[Maintenance Guide](./docs/maintenance-guide.md)** for:
- Pausing/unpausing oracle
- Adding/removing operators
- Updating feed configurations
- Handling stuck rounds
- Integration testing after changes

**Quick reference:**
```bash
# Pause oracle
cast send $ORACLE "pause()" --rpc-url $RPC_URL --private-key $PK

# Add operator to feed
cast send $ORACLE "addOperator(bytes32,address)" $FEED_ID $OPERATOR --rpc-url $RPC_URL --private-key $PK

# Unpause oracle
cast send $ORACLE "unpause()" --rpc-url $RPC_URL --private-key $PK
```

---

## Architecture & Design

### Core Components

- **PriceLoomOracle**: Multi-feed oracle with EIP-712 submissions and median aggregation
- **PriceLoomAdapterFactory**: Deploys Chainlink-compatible adapters
- **AggregatorV3Adapter**: Chainlink interface wrapper for single feed
- **Operator Bot**: Automated price submission service (testing/reference)

### Key Features

- **Multi-feed architecture**: One oracle contract manages multiple price feeds
- **EIP-712 signatures**: Gas-efficient off-chain signing for submissions
- **Median aggregation**: On-chain median calculation from operator submissions
- **Chainlink compatibility**: Drop-in replacement via adapter interface
- **Pause/unpause**: Emergency pause for maintenance operations
- **Round timeout**: Automatic stale price handling with roll-forward

See **[Oracle Design](./docs/oracle-design-v0.md)** for complete technical specification.

---

## Network Shortcuts

Use make targets with network prefixes for convenience:

```bash
# Local Anvil (auto-sets RPC=http://127.0.0.1:8545, CHAIN_ID=31337)
make anvil-bootstrap-all
make anvil-deploy-factory

# Alphanet (auto-sets RPC=https://alphanet.load.network, CHAIN_ID=9496)
make alphanet-deploy-factory
make alphanet-create-feeds-json

# Check configuration
make doctor  # Prints RPC_URL, CHAIN_ID, and live chain-id
```

All targets verify chain-id before broadcasting to prevent signature mismatches.
