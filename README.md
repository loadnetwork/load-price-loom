# Price Loom Oracle

Price Loom is a multi-feed, push-based price oracle for EVM chains. It features EIP-712 signed submissions for gas-efficient updates, on-chain median aggregation, and a Chainlink-compatible adapter for easy integration with the existing DeFi ecosystem.

This document provides a comprehensive guide for developers, administrators, and operators.

**Quick Links**
- **[For Consumers: How to Read Prices](./docs/consumer-guide.md)**
- **[For Operators: How to Push Prices](./docs/operator-guide.md)**
- **[For Maintainers: Admin & Ops Guide](./docs/maintenance-guide.md)**
- **[For Architects: Core Design Docs](./docs/oracle-design-v0.md)**

---

## 1. Development Workflow

This section guides you through setting up the project, from first clone to running a local deployment.

### Prerequisites
- [Foundry](https://getfoundry.sh/)
- [Git](https://git-scm.com/)

### Initial Setup

1.  **Clone & Install:** Clone the repository and install all dependencies.
    ```bash
    git clone <repository-url>
    cd load-price-loom
    git submodule update --init --recursive
    forge install
    ```

2.  **Build & Test:** Ensure everything is working correctly by building the contracts and running the test suite.
    ```bash
    make test
    ```

### Local Quick Start: Running a Test Deployment

This workflow lets you deploy and interact with the entire oracle system on a local Anvil node in minutes.

1.  **Prepare Environment File:**
    The deployment scripts use an `.env` file for private keys. The provided example file is pre-filled with standard Anvil test keys.
    ```bash
    cp .env.example .env
    ```

2.  **Start a Local Node:**
    In a separate terminal, start a local Anvil node.
    ```bash
    # Default Anvil chain-id is 31337. If you want it to match Alphanet (9496), use:
    # anvil --chain-id 9496
    anvil
    ```

3.  **Deploy Everything:**
    The `bootstrap-all` command deploys a new oracle, a new factory, and then configures all feeds and adapters from `feeds.json` in a single step. The `ADMIN` for the oracle will be Anvil's default deployer address, taken from the `PRIVATE_KEY` in your `.env` file.
    ```bash
    # This command reads .env for the ADMIN private key and RPC_URL
    # Tip: use the anvil- prefix to auto-set RPC/chain-id for local dev
    make anvil-bootstrap-all
    ```
    You will see the deployed addresses of the oracle and factory, followed by the feeds and adapters created.

---

## 2. Production Deployment & Operations

While `bootstrap-all` is great for testing, a production deployment requires a more deliberate, step-by-step approach for maximum safety and control.

### Configuration

- **`feeds.json`:** Before starting, ensure your `feeds.json` file is complete and accurate. This file is the source of truth for all feed parameters and operator sets for the target environment (e.g., mainnet).
- **`.env`:** Create a `.env` file and populate it with the secure, production private keys and the correct `RPC_URL` for your target network.

### Modular Deployment Workflow (Recommended)

This workflow allows you to verify each major step before proceeding to the next.

**Step 1: Deploy the Oracle**
Manually deploy the `PriceLoomOracle` contract, passing the secure admin address (e.g., a Multi-Sig wallet) to the constructor. Note the deployed oracle address.

**Step 2: Deploy the Adapter Factory**
```bash
# Set the address of the newly deployed oracle
export ORACLE=0xYourOracleAddress
# Alphanet (chain-id 9496)
make alphanet-deploy-factory
# or, explicitly
# make deploy-factory RPC_URL=https://alphanet.load.network CHAIN_ID=9496
```
Note the logged address of the new `PriceLoomAdapterFactory`.

**Step 3: Create On-Chain Feeds**
This step reads `feeds.json` and calls `createFeed` for each entry.
```bash
export ORACLE=0xYourOracleAddress
make alphanet-create-feeds-json
```

**Step 4: Deploy Feed Adapters**
This deploys the deterministic `AggregatorV3Adapter` for each feed.
```bash
export FACTORY=0xYourFactoryAddress
make alphanet-deploy-adapters-json
```

### Maintenance

- **Adding/Modifying Feeds:** Update `feeds.json`, then re-run `make create-feeds-json` and `make deploy-adapters-json`.
- **Emergency Operations:** For non-standard tasks, the `docs/maintenance-guide.md` provides lower-level `cast` commands for direct contract interaction (e.g., pausing, removing a single operator).
- **Poking Stuck Rounds:** The `poke-feeds-json` target is a convenient way to handle timeouts for all feeds defined in your `feeds.json`.
  ```bash
  export ORACLE=0xYourOracleAddress
  make alphanet-poke-feeds-json
  ```

---

## 3. End‑to‑End Local Demo (Anvil)

This demo deploys a test feed (`ar/bytes-testv1`), a Chainlink adapter, a minimal consumer, and runs 5 local operators (Anvil accounts) that push prices every 30 seconds.

1) Start Anvil in a separate terminal:
```bash
anvil --chain-id 31337
```

2) Bootstrap oracle + factory + feeds + adapters using the Anvil feed config:
```bash
export ADMIN=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266  # anvil[0]
make anvil-bootstrap-all FEEDS_FILE=feeds-anvil.json
```

3) Deploy the example consumer bound to the adapter (set ADAPTER to the logged adapter address):
```bash
export ADAPTER=0xAdapter
make anvil-doctor   # optional: prints RPC/chain-id
forge script script/DeployTestConsumer.s.sol:DeployTestConsumer --rpc-url http://127.0.0.1:8545 --chain-id 31337 --broadcast -vvvv
```

4) Run the operator bot (Node.js, ethers v6):
```bash
npx --yes ethers@6.13.2  >/dev/null 2>&1 || true  # ensure ethers installed
node scripts/bot/operators-bot.js \
  --rpc http://127.0.0.1:8545 \
  --oracle 0xOracle \
  --feedDesc "ar/bytes-testv1" \
  --interval 30000
```

You should see periodic submissions from 5 operators and the round finalizing on each cycle. You can query the consumer contract’s `latest()` to verify updated prices.

### Network Shortcuts & Safety
- Use `anvil-<target>` or `alphanet-<target>` prefixes (e.g., `anvil-deploy-factory`, `alphanet-create-feeds-json`). These set `RPC_URL` and `CHAIN_ID` for you.
- `make doctor` prints your current `RPC_URL`, `CHAIN_ID`, and the live chain-id at the RPC to help diagnose mismatches.
- All script targets verify the remote chain-id before broadcasting and sign with the provided chain-id (prevents domain/signature mismatches).

---

## 4. Operating a Price Node

An operator is responsible for running an off-chain service that provides reliable and timely price data. For a full implementation guide, refer to **`docs/operator-guide.md`**.

### Operator Responsibilities

1.  **Secure Key Management:** Your operator key is critical. **Do not expose it.** Use a secure vault, KMS, or HSM in production.
2.  **Data Redundancy:** Your service should fetch data from multiple, highly-reliable sources and have logic to handle unresponsive or outlier APIs.
3.  **Reliable Infrastructure:** Run your service on a resilient server with monitoring and alerting to ensure high uptime.

### Submission Workflow

The core logic is detailed in the operator guide, but involves:
1.  Fetching and validating prices from your sources.
2.  Constructing an EIP-712 `PriceSubmission` message.
3.  Signing the message with your operator key.
4.  Submitting the signature to the oracle via the `submitSigned` function.
