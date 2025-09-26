# Chainlink Adapter Guide (AggregatorV3-Compatible)

## Motivation
- Many DeFi apps and tools expect Chainlink's `AggregatorV3Interface` at a dedicated address per price feed (no feedId parameter).
- Our core oracle is multi-feed and keyed by `bytes32 feedId`. The adapter bridges this difference: one small contract per feed exposes `AggregatorV3Interface` and delegates reads to the core `PriceLoomOracle` for a fixed `feedId`.
- Benefits:
  - Plug-and-play with existing Chainlink consumers.
  - No duplication of logic; adapter is read-only and minimal.

## Architecture
- `PriceLoomAggregatorV3Adapter` stores:
  - `IOracleReader oracle` (core oracle address)
  - `bytes32 feedId` (fixed at deployment)
- Exposes:
  - `decimals()` and `description()` via `oracle.getConfig(feedId)`
- `latestRoundData()` via `oracle.latestRoundData(feedId)`; adapter normalizes missing data errors to `"No data present"` (Chainlink parity).
- `getRoundData(roundId)`: delegates to `oracle.getRoundData(feedId, roundId)`; adapter normalizes evicted/missing rounds to `"No data present"`.
- One adapter per feed. For N feeds, deploy N adapters (or use the factory).

## Files
- `src/adapter/PriceLoomAggregatorV3Adapter.sol`
- `src/adapter/PriceLoomAdapterFactory.sol`
- `src/interfaces/AggregatorV3Interface.sol`
- Example deploy script for AR/byte feed: `script/DeployArByteAdapter.s.sol`

## Deploying an Adapter (Example: AR/byte)
1) Compute feedId: `bytes32 feedId = keccak256(abi.encodePacked("AR/byte"));`
2) Have your core oracle deployed (address = `ORACLE`).
3) Use the Foundry script:
   - Set env var `ORACLE` to your oracle address
   - Run:
     - `forge script script/DeployArByteAdapter.s.sol:DeployArByteAdapter --rpc-url <RPC> --broadcast -vvvv`
   - Output logs the adapter address for the AR/byte feed.

## Deploying via Factory (Multiple Feeds)
1) Deploy the factory with your oracle address:
   - Solidity: `new PriceLoomAdapterFactory(IOracleReader(oracleAddr))`
2) For each feedId call:
   - `factory.deployAdapter(feedId)` → emits `AdapterDeployed(feedId, adapter)`
   - Note: The factory requires that the feed exists (created in the oracle). It reverts with `feed not found` if not.
3) Store adapter addresses for your integrations.

### Deterministic Deployment (CREATE2)
- For stable, predictable addresses per `feedId`, use:
  - `factory.deployAdapterDeterministic(feedId)`
- Address is computed with salt = `feedId`. A second call with the same salt reverts.
- Predict on-chain via factory helper:
  - `factory.computeAdapterAddress(feedId) -> address`
- Off-chain (ethers v5):
```ts
import { getCreate2Address, keccak256, defaultAbiCoder, hexConcat } from "ethers/lib/utils";
import { utils } from "ethers";

const initCode = hexConcat([
  // creation code
  PriceLoomAggregatorV3Adapter__factory.bytecode,
  // constructor args (oracle, feedId)
  defaultAbiCoder.encode(["address","bytes32"],[oracle, feedId])
]);
const initCodeHash = keccak256(initCode);
const predicted = getCreate2Address(factory, feedId, initCodeHash);
```

## Consumer Usage
- Solidity (typical Chainlink consumer):
```solidity
import {AggregatorV3Interface} from "path/to/AggregatorV3Interface.sol";

contract UsesPrice {
    AggregatorV3Interface public immutable priceFeed;

    constructor(address adapter) {
        priceFeed = AggregatorV3Interface(adapter);
    }

    function latest() external view returns (int256 answer, uint256 updatedAt) {
        (, int256 a,, uint256 u,) = priceFeed.latestRoundData();
        return (a, u);
    }
}
```

- Ethers.js:
```ts
const abi = [
  "function latestRoundData() view returns (uint80,int256,uint256,uint256,uint80)",
  "function decimals() view returns (uint8)",
  "function description() view returns (string)"
];
const feed = new ethers.Contract(adapterAddress, abi, provider);
const [roundId, answer, startedAt, updatedAt, answeredInRound] = await feed.latestRoundData();
const decimals = await feed.decimals();
```

## Notes & Options
- Decimals/description reflect the feed's config in the core oracle.
- Historical reads: core stores a 128‑round ring buffer. `getRoundData(roundId)` reverts if the round is evicted/outside the window.
- Security: adapter is read-only; no special roles. Ensure the `oracle` address is correct at deploy time.
- Adapter validity: The adapter constructor checks that the feed exists in the oracle. This prevents deploying unusable adapters for non-existent feeds.
- Feed naming: prefer stable descriptors like `"AR/byte"` and version suffixes when needed, e.g., `"AR/byte:v1"`.

## Troubleshooting
- If a Chainlink-based dapp shows wrong decimals/description, verify feed config in the oracle.
- If consumers rely on historical `getRoundData`, either revert in adapter (to fail fast) or implement historical storage in the core before enabling those paths.
- For multiple feeds, confirm you deployed one adapter per distinct `feedId`.
