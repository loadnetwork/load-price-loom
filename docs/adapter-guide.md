# Chainlink Adapter Guide (AggregatorV3-Compatible)

## Motivation
- Many DeFi apps and tools expect Chainlink's `AggregatorV3Interface` at a dedicated address per price feed (no feedId parameter).
- Our core oracle is multi-feed and keyed by `bytes32 feedId`. The adapter bridges this difference: one small contract per feed exposes `AggregatorV3Interface` and delegates reads to the core `PriceLoomOracle` for a fixed `feedId`.
- Benefits:
  - Plug-and-play with existing Chainlink consumers.
  - No duplication of logic; adapter is read-only and minimal.

## ⚠️ Production Considerations

### Round ID Continuity

The current adapter implementation (`PriceLoomAggregatorV3Adapter`) uses **single-phase round IDs**. This means:

- ✅ Works perfectly for single oracle deployments
- ❌ **Historical round IDs break if oracle address changes**
- ❌ **Consumers must be updated manually when upgrading oracle**

For production mainnet deployments, implement **phase-aware adapters** to support:
- Stable adapter address across oracle upgrades
- Historical continuity (old round IDs remain valid)
- Chainlink-compatible phase encoding: `roundId = (phaseId << 64) | aggregatorRoundId`

See [phase-support-roadmap.md](./phase-support-roadmap.md) for full implementation details and [pre-mainnet-checklist.md](./pre-mainnet-checklist.md) for deployment planning.

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

**Predicting addresses:**

- **On-chain** (recommended):
  ```solidity
  address predicted = factory.computeAdapterAddress(feedId);
  ```

- **Off-chain with ethers v6**:
  ```ts
  import { ethers } from "ethers";

  // Get factory contract
  const factory = new ethers.Contract(factoryAddress, factoryAbi, provider);

  // Use factory helper to predict address
  const predictedAddress = await factory.computeAdapterAddress(feedId);

  // Or compute manually with CREATE2:
  const initCode = ethers.concat([
    adapterBytecode,
    ethers.AbiCoder.defaultAbiCoder().encode(["address", "bytes32"], [oracle, feedId])
  ]);
  const initCodeHash = ethers.keccak256(initCode);
  const predicted = ethers.getCreate2Address(factory, feedId, initCodeHash);
  ```

**Note:** Using the factory's `computeAdapterAddress()` is simpler and more reliable than manual CREATE2 calculation.

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

## Testing Integration

After deploying adapters, verify the full stack with the integration test script:

```bash
# Set deployed addresses
export ORACLE=0x5FbDB2315678afecb367f032d93F642f64180aa3
export ADAPTER=0xD9164F568A7d21189F61bd53502BdE277883A0A2
export CONSUMER=0x610178dA211FEF7D417bC0e6FeD39F05609AD788

# Run integration test
node scripts/test-adapter-consumer.mjs
```

This tests:
1. **Oracle**: Fetches `latestRoundData(feedId)` and `getConfig(feedId)`
2. **Adapter**: Verifies Chainlink-compatible interface returns same data
3. **Consumer**: Confirms consumer contract reads correctly through adapter
4. **Historical Data**: Tests `getRoundData(roundId)` for past rounds

Expected output:
```
✅ Latest Round Data:
   Round ID:     11
   Answer:       9992000030 (99.9200003)
   Decimals:     8

✅ Adapter data matches Oracle
✅ Consumer data matches Oracle & Adapter
```

See `scripts/test-adapter-consumer.mjs` for the full test implementation.

## Troubleshooting
- If a Chainlink-based dapp shows wrong decimals/description, verify feed config in the oracle.
- If consumers rely on historical `getRoundData`, either revert in adapter (to fail fast) or implement historical storage in the core before enabling those paths.
- For multiple feeds, confirm you deployed one adapter per distinct `feedId`.
- If integration test fails with "No data present", ensure operator bot has submitted prices (see [Operator Guide](./operator-guide.md)).

---

## Related Documentation

- **[Consumer Guide](./consumer-guide.md)** - How to read prices via adapters in your contracts
- **[Deployment Cookbook](./deployment-cookbook.md)** - Deploy adapters with factory
- **[Scripts & Bots](../scripts/README.md)** - Integration testing tools
- **[Phase Support Roadmap](./phase-support-roadmap.md)** - Future upgrade path for production
- **[Pre-Mainnet Checklist](./pre-mainnet-checklist.md)** - Production readiness requirements
