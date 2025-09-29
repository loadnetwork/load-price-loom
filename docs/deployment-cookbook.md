# Deployment Cookbook

Scenarios, commands, and copy‑paste snippets for common tasks.

## Addresses & IDs
- Compute feedId (bytes32): `keccak256(abi.encodePacked("AR/byte"))`
- Predict adapter address (deterministic): via factory `computeAdapterAddress(feedId)`

## New Oracle + Factory + Feeds + Adapters (One Shot)
```bash
export ADMIN=0xAdmin
make bootstrap-all RPC_URL=$ALPHA_RPC_URL
```

## Modular Flow (Production)
1) Deploy oracle (ensure admin secure)
2) Deploy factory bound to oracle
```bash
export ORACLE=0xOracle
make deploy-factory RPC_URL=$ALPHA_RPC_URL
```
3) Create feeds from JSON
```bash
make create-feeds-json ORACLE=$ORACLE FEEDS_FILE=feeds.json RPC_URL=$ALPHA_RPC_URL
```
4) Deploy adapters
```bash
export FACTORY=0xFactory
make deploy-adapters-json FACTORY=$FACTORY FEEDS_FILE=feeds.json RPC_URL=$ALPHA_RPC_URL
```

## Create One Feed (Env‑Driven)
```bash
export ORACLE=0xOracle
export FEED_DESC="AR/byte"
export DECIMALS=8 MIN_SUBMISSIONS=2 MAX_SUBMISSIONS=3
export HEARTBEAT_SEC=3600 DEVIATION_BPS=50 TIMEOUT_SEC=900
export MIN_PRICE=0 MAX_PRICE=10000000000000000000000
export DESCRIPTION="AR/byte"
export OPERATORS_JSON='["0xOp1","0xOp2","0xOp3"]'
make create-feed-env RPC_URL=$ALPHA_RPC_URL
```

## Pause, Poke, Config Changes
- Pause submissions:
```bash
cast send $ORACLE "pause()" --rpc-url $RPC_URL --private-key $PK
```
- Poke feeds from JSON (while paused is allowed):
```bash
make poke-feeds-json ORACLE=$ORACLE FEEDS_FILE=feeds.json RPC_URL=$ALPHA_RPC_URL
```
- Update config (ensure no open round for that feed):
```bash
# Example: set feed config via ABI
cast send $ORACLE "setFeedConfig(bytes32,(uint8,uint8,uint8,uint8,uint32,uint32,uint32,int256,int256,string))" \
  $FEED_ID "(8,2,3,0,3600,50,900,0,10000000000000000000000,'AR/byte')" \
  --rpc-url $RPC_URL --private-key $PK
```

## Add/Remove Operators
```bash
# Add
cast send $ORACLE "addOperator(bytes32,address)" $FEED_ID 0xOp \
  --rpc-url $RPC_URL --private-key $PK

# Remove
cast send $ORACLE "removeOperator(bytes32,address)" $FEED_ID 0xOp \
  --rpc-url $RPC_URL --private-key $PK
```

## Consumer Freshness (Solidity)
```solidity
(uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = oracle.latestRoundData(feedId);
require(roundId == answeredInRound, "stale-forwarded");
require(block.timestamp - updatedAt <= MAX_DELAY, "stale-age");
```

## Off‑Chain Signing (TS, ethers v6)
See README or `docs/operator-guide.md` for a complete example.

