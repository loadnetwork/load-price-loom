# Getting Started

This guide helps you set up the repository, run tests, and deploy an oracle + adapters in minutes.

## Prerequisites
- Foundry (forge, cast): https://book.getfoundry.sh/
- Git
- A funded deployer key for your target network

## Clone, Install, Test
```bash
git clone <repo-url>
cd load-price-loom
git submodule update --init --recursive
forge install
forge build
forge test
```

## Network Shortcuts
- Alphanet: chain-id `9496`, RPC `https://alphanet.load.network`
- Anvil (local): chain-id `31337` by default; you can start it with `--chain-id 9496` to mirror Alphanet for EIP‑712 domains.

Use prefixed make targets to auto-set RPC and chain-id:
```bash
# Alphanet
make alphanet-deploy-factory

# Anvil
make anvil-bootstrap-all FEEDS_FILE=feeds-anvil.json

# Diagnostics
make doctor      # prints RPC_URL/CHAIN_ID and remote chain-id
```

## One‑Command Bootstrap
Deploy a fresh oracle and factory, then create feeds and deterministic adapters from `feeds.json`:
```bash
# ADMIN is the on-chain admin address that receives roles
export ADMIN=0xYourAdminAddress
make alphanet-bootstrap-all
```
Outputs include oracle/factory addresses and adapter addresses per feed.

## Modular Deployment
Prefer this route for production:
```bash
# 1) Deploy oracle manually or via your own script
# 2) Deploy factory bound to oracle (Alphanet)
export ORACLE=0xOracle
make alphanet-deploy-factory

# 3) Create feeds from feeds.json
make alphanet-create-feeds-json ORACLE=$ORACLE

# 4) Deploy deterministic adapters
export FACTORY=0xFactory
make alphanet-deploy-adapters-json FACTORY=$FACTORY
```

## Running an Operator
See `docs/operator-guide.md` for a copy‑paste EIP‑712 signing example (ethers v6) and operational best practices.

## Consuming Prices
DeFi‑style consumers can read via the adapter (`AggregatorV3Interface`) or directly from the oracle. See `docs/consumer-guide.md` for code snippets and freshness checks.
