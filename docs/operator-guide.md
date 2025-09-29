# Price Loom Operator Guide

This guide provides off-chain operators with the necessary steps and code examples to sign and submit price data to the `PriceLoomOracle` contract.

## Overview

As an operator, your primary role is to fetch price data from reliable sources, sign this data using your private key, and ensure it is submitted to the oracle. Submissions are made via EIP-712 typed data signatures, which means another party (a "relayer") can submit your signed message on your behalf, saving you from paying gas for every submission.

## Submission Workflow

1.  **Fetch Price Data:** Get the current price for the feed you are responsible for (e.g., AR/byte).
2.  **Determine Round ID:** Query the oracle contract to find the correct `roundId` to sign for.
3.  **Construct Submission:** Create the `PriceSubmission` data structure.
4.  **Sign Typed Data:** Use your operator private key to sign the EIP-712 `PriceSubmission` data.
5.  **Submit Signature:** Call the `submitSigned` function on the `PriceLoomOracle` contract, passing in the submission data and your signature.

## TypeScript Example (using Ethers.js v5)

This example demonstrates the complete process of signing and submitting a price.

### 1. Setup

First, ensure you have `ethers` installed in your project:

```bash
npm install ethers
```

### 2. Code Example

Save the following code as `submitPrice.ts`. This script reads your operator private key from an environment variable, constructs the submission, signs it, and sends it to the contract.

```typescript
import { ethers } from "ethers";

// ABI fragment for the PriceLoomOracle contract
const oracleAbi = [
    "function submitSigned(bytes32 feedId, tuple(bytes32 feedId, uint80 roundId, int256 answer, uint256 validUntil) sub, bytes sig)",
    "function nextRoundId(bytes32 feedId) external view returns (uint80)",
    "function priceSubmissionTypehash() external pure returns (bytes32)",
    "function domainSeparator() external view returns (bytes32)"
];

// --- Configuration ---
const ORACLE_ADDRESS = "0xYourOracleAddressHere"; // TODO: Replace with your oracle's address
const RPC_URL = "https://your.rpc.url"; // TODO: Replace with your RPC endpoint
const OPERATOR_PRIVATE_KEY = process.env.OPERATOR_PRIVATE_KEY;

const FEED_NAME = "AR/byte";
const PRICE_TO_SUBMIT = ethers.utils.parseUnits("0.000000123", 18); // Example: 123 winston/byte, scaled to 18 decimals
// --- End Configuration ---

async function main() {
    if (!OPERATOR_PRIVATE_KEY) {
        throw new Error("OPERATOR_PRIVATE_KEY environment variable not set!");
    }

    // 1. Connect to the blockchain
    const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
    const signer = new ethers.Wallet(OPERATOR_PRIVATE_KEY, provider);
    const oracle = new ethers.Contract(ORACLE_ADDRESS, oracleAbi, signer);

    console.log(`Using operator address: ${signer.address}`);

    // 2. Define EIP-712 domain and types
    const domain = {
        name: "Price Loom",
        version: "1",
        chainId: (await provider.getNetwork()).chainId,
        verifyingContract: ORACLE_ADDRESS
    };

    const types = {
        PriceSubmission: [
            { name: "feedId", type: "bytes32" },
            { name: "roundId", type: "uint80" },
            { name: "answer", type: "int256" },
            { name: "validUntil", type: "uint256" }
        ]
    };

    // 3. Construct the submission data
    const feedId = ethers.utils.id(FEED_NAME); // keccak256("AR/byte")
    const roundId = await oracle.nextRoundId(feedId);
    const validUntil = Math.floor(Date.now() / 1000) + 300; // Signature is valid for 5 minutes

    const submission = {
        feedId: feedId,
        roundId: roundId,
        answer: PRICE_TO_SUBMIT,
        validUntil: validUntil
    };

    console.log("\nSigning submission:");
    console.log(submission);

    // 4. Sign the typed data
    const signature = await signer._signTypedData(domain, types, submission);

    console.log(`\nSignature: ${signature}`);

    // 5. Submit the signed price to the oracle
    try {
        console.log("\nSubmitting transaction...");
        const tx = await oracle.submitSigned(feedId, submission, signature);
        console.log(`Transaction sent! Hash: ${tx.hash}`);

        const receipt = await tx.wait();
        console.log(`Transaction mined! Gas used: ${receipt.gasUsed.toString()}`);

    } catch (error) {
        console.error("\nTransaction failed!");
        // The error object often contains useful details
        if (error.reason) {
            console.error(`Reason: ${error.reason}`);
        }
        // console.error(error);
    }
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
```

### 3. How to Run

1.  **Set Environment Variable:**

    ```bash
    export OPERATOR_PRIVATE_KEY="0xYourPrivateKeyHere"
    ```

2.  **Run the Script:**

    You will need `ts-node` to run the TypeScript file directly.

    ```bash
    npm install -g ts-node
    ts-node submitPrice.ts
    ```

## Common Revert Reasons

-   `Expired()`: Your signature's `validUntil` timestamp has passed. Check that your system clock is synchronized.
-   `WrongRound()`: The `roundId` you signed for is not the current open round. This can happen if a new round started after you fetched the `nextRoundId` but before your transaction was mined.
-   `DuplicateSubmission()`: Your operator address has already submitted a price for this round.
-   `NotOperator()`: The signing key does not correspond to a registered operator for this feed.
-   `OutOfBounds()`: The price you submitted is outside the `minPrice`/`maxPrice` configured for the feed.
