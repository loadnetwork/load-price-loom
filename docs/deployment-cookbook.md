# Deployment Cookbook

Scenarios, commands, and copy‑paste snippets for common tasks.

## Addresses & IDs
- Compute feedId (bytes32): `keccak256(abi.encodePacked("AR/byte"))`
- Predict adapter address (deterministic): via factory `computeAdapterAddress(feedId)`

## New Oracle + Factory + Feeds + Adapters (One Shot)
```bash
export ADMIN=0xAdmin
# Alphanet shortcut
make alphanet-bootstrap-all
# or local Anvil
make anvil-bootstrap-all FEEDS_FILE=feeds-anvil.json
```

## Modular Flow (Production)
1) Deploy oracle (ensure admin secure)
2) Deploy factory bound to oracle
```bash
export ORACLE=0xOracle
make alphanet-deploy-factory
```
3) Create feeds from JSON
```bash
make alphanet-create-feeds-json ORACLE=$ORACLE FEEDS_FILE=feeds.json
```
4) Deploy adapters
```bash
export FACTORY=0xFactory
make alphanet-deploy-adapters-json FACTORY=$FACTORY FEEDS_FILE=feeds.json
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
make alphanet-create-feed-env
```

## Pause, Poke, Config Changes
- Pause submissions:
```bash
cast send $ORACLE "pause()" --rpc-url $RPC_URL --private-key $PK
```
- Poke feeds from JSON (while paused is allowed):
```bash
make alphanet-poke-feeds-json ORACLE=$ORACLE FEEDS_FILE=feeds.json
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

## Network Safety & Diagnostics
- Use `anvil-<target>` or `alphanet-<target>` prefixed make targets to auto-set RPC_URL and CHAIN_ID.
- `make doctor` prints the selected RPC/CHAIN_ID and the live chain-id from the RPC.
- All script targets verify the remote chain-id before broadcasting and pass `--chain-id` to sign with the correct domain.
