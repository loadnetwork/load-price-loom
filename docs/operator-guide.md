# Operator Guide

Operators sign EIP‑712 price submissions off‑chain and relay them on‑chain. This guide covers responsibilities, code snippets, and best practices.

**Quick Start:** For local testing, use the provided operator bot at `scripts/bot/operators-bot.mjs`. For production, follow the detailed setup below.

## Responsibilities
- Secure key management (HSM or well‑managed hot wallet).
- Data quality (multiple upstream sources, sanity checks, outlier filtering).
- Timeliness (submit per heartbeat, or when deviation threshold is crossed).

## EIP‑712 Typed Data
Type: `PriceSubmission(bytes32 feedId,uint80 roundId,int256 answer,uint256 validUntil)`
Domain: `{ name: "Price Loom", version: "1", chainId, verifyingContract }`

## Signing & Submitting (ethers v6)
```ts
import { ethers } from "ethers";

const oracle = new ethers.Contract(ORACLE_ADDRESS, [
  "function nextRoundId(bytes32) view returns (uint80)",
  "function dueToStart(bytes32,int256) view returns (bool)",
  "function getConfig(bytes32) view returns (tuple(uint8,uint8,uint8,uint8,uint32,uint32,uint32,int256,int256,string))",
  "function submitSigned(bytes32,(bytes32,uint80,int256,uint256),bytes)"
], provider);

const feedId = FEED_ID; // keccak256(abi.encodePacked("AR/byte"))
const proposed = 101n * 10n ** 8n; // example price at decimals=8

let round = await oracle.nextRoundId(feedId);
const allowOpen = await oracle.dueToStart(feedId, proposed);
// If no open round yet and not due to start, wait until heartbeat or sufficient deviation

const submission = {
  feedId,
  roundId: round,
  answer: proposed,
  validUntil: BigInt(Math.floor(Date.now()/1000) + 60),
};

const domain = {
  name: "Price Loom",
  version: "1",
  chainId: (await provider.getNetwork()).chainId,
  verifyingContract: ORACLE_ADDRESS,
};

const types = {
  PriceSubmission: [
    { name: "feedId", type: "bytes32" },
    { name: "roundId", type: "uint80" },
    { name: "answer", type: "int256" },
    { name: "validUntil", type: "uint256" },
  ],
};

const sig = await signer.signTypedData(domain, types, submission);
const tx = await oracle.submitSigned(feedId, submission, sig);
await tx.wait();
```

## Reference Implementation: Operator Bot

For local testing and as a reference implementation, see `scripts/bot/operators-bot.mjs`. This bot demonstrates:

- **Sequential submission pattern** (prevents race conditions)
- **Automatic recovery** via `poke()` when rounds get stuck
- **Graceful error handling** for all oracle error types
- **Pause detection** and automatic resume
- **Round state tracking** with `nextRoundId()` queries

### Running the Test Bot

```bash
# Install dependencies
npm install

# Run the bot (local Anvil example)
node scripts/bot/operators-bot.mjs \
  --rpc http://127.0.0.1:8545 \
  --oracle 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
  --feedDesc "ar/bytes-testv1" \
  --interval 30000

# Or with environment variables
export RPC_URL=http://127.0.0.1:8545
export ORACLE=0x5FbDB...
export FEED_DESC="ar/bytes-testv1"
export INTERVAL_MS=30000
node scripts/bot/operators-bot.mjs
```

**Note:** The test bot uses default Anvil keys. For production, set `PRIVATE_KEYS_JSON` environment variable.

### Bot Features

1. **Dynamic Operator Initialization**: Automatically matches on-chain registered operators with available private keys
2. **Sequential Submissions**: Avoids race conditions by submitting one operator at a time
3. **State Adaptation**: Re-queries `nextRoundId()` before each submission to detect round changes
4. **Early Exit**: Stops after quorum reached (minSubmissions)
5. **Recovery Logic**: Calls `poke()` after 2 consecutive failed ticks
6. **Comprehensive Logging**: Shows submission status, round progression, price age, and staleness

See [operator-bot-fix-report.md](./operator-bot-fix-report.md) for detailed architecture and troubleshooting.

## Best Practices
- Always compute `roundId` via `nextRoundId(feedId)` and validate with `dueToStart` when opening a new round.
- **Use sequential submissions** for deterministic behavior (see bot implementation).
- Keep `validUntil` short (e.g., 60–120s).
- Keep your time source synced (NTP).
- Monitor `isStale(feedId, maxDelay)` and alerts on missed heartbeats/deviations.
- Rotate operators via admin flow as needed.
- **MEV Protection**: Consider using private mempools (e.g., Flashbots, MEV-Blocker) to prevent front-running of price submissions. While submissions are signed off-chain and can't be modified, they can be extracted and potentially manipulated by MEV bots in public mempools.

## Common Revert Reasons

-   `Expired()`: Your signature's `validUntil` timestamp has passed. Check that your system clock is synchronized.
-   `WrongRound()`: The `roundId` you signed for is not the current open round. This can happen if a new round started after you fetched the `nextRoundId` but before your transaction was mined.
-   `DuplicateSubmission()`: Your operator address has already submitted a price for this round.
-   `NotOperator()`: The signing key does not correspond to a registered operator for this feed.
-   `OutOfBounds()`: The price you submitted is outside the `minPrice`/`maxPrice` configured for the feed.

---

## Production Considerations

While the script above is a functional example, a production-grade operator requires additional robustness and security.

### 1. Secure Key Management

Storing a plaintext private key in an environment variable is **not secure** for production. Use a dedicated key management solution:
-   **Hardware Security Module (HSM):** For the highest level of security.
-   **Managed KMS:** Cloud provider services like AWS KMS, Google Cloud KMS, or Azure Key Vault.
-   **Self-Hosted Vault:** Tools like HashiCorp Vault.

Your application should request a signature from these systems without ever accessing the raw private key.

### 2. Data Source Redundancy

Do not rely on a single API for price data. Your service should:
-   Fetch data from multiple, independent, and highly-reputable sources (e.g., Binance, Coinbase, Kraken, CoinGecko).
-   Implement logic to validate and aggregate these prices, for example, by taking the median or a volume-weighted average.
-   Include sanity checks to discard outlier sources that deviate significantly from the aggregate.

### 3. Monitoring and Alerting

Your operator node is critical infrastructure. You must have monitoring in place to alert you to problems:
-   **Submission Success:** Monitor your transactions to ensure they are being successfully mined. Alert on consecutive failures.
-   **Price Deviation:** Alert if your sourced price deviates significantly from the current on-chain median. This could indicate an issue with your sources or a market event.
-   **Gas Tank:** Monitor the balance of the address used for submitting transactions and alert when it runs low.
-   **System Health:** Monitor the health (CPU, memory, etc.) of the server running your operator service.


---

## Related Documentation

- **[Scripts & Bots](../scripts/README.md)** - Operator bot reference and commands
- **[Deployment Cookbook](./deployment-cookbook.md)** - Deploy oracle and configure feeds
- **[Maintenance Guide](./maintenance-guide.md)** - Manage operators and feed configs
- **[Local Development Guide](./local-development-guide.md)** - Test operator workflows locally
- **[Oracle Design](./oracle-design-v0.md)** - Technical specification and architecture
- **[Operator Bot Fix Report](./operator-bot-fix-report.md)** - Detailed bot architecture and troubleshooting
