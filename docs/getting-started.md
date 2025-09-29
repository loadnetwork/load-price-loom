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

## Defaults (Alphanet)
- Chain ID: `9496`
- RPC: `https://alphanet.load.network`
Set envs (or copy `.env.example`):
```bash
export ALPHA_RPC_URL=https://alphanet.load.network
export CHAIN_ID=9496
```

## One‑Command Bootstrap
Deploy a fresh oracle and factory, then create feeds and deterministic adapters from `feeds.json`:
```bash
# ADMIN is the on-chain admin address that receives roles
export ADMIN=0xYourAdminAddress
make bootstrap-all RPC_URL=$ALPHA_RPC_URL
```
Outputs include oracle/factory addresses and adapter addresses per feed.

## Modular Deployment
Prefer this route for production:
```bash
# 1) Deploy oracle manually or via your own script
# 2) Deploy factory bound to oracle
export ORACLE=0xOracle
make deploy-factory RPC_URL=$ALPHA_RPC_URL

# 3) Create feeds from feeds.json
make create-feeds-json ORACLE=$ORACLE RPC_URL=$ALPHA_RPC_URL

# 4) Deploy deterministic adapters
export FACTORY=0xFactory
make deploy-adapters-json FACTORY=$FACTORY RPC_URL=$ALPHA_RPC_URL
```

## Running an Operator
See `docs/operator-guide.md` for a copy‑paste EIP‑712 signing example (ethers v6) and operational best practices.

## Consuming Prices
DeFi‑style consumers can read via the adapter (`AggregatorV3Interface`) or directly from the oracle. See `docs/consumer-guide.md` for code snippets and freshness checks.

