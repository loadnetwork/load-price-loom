
  Let's verify the oracle configuration and initial state:

  # Check feed configuration
  cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
    "getConfig(bytes32)" \
    0x3f32666a158724369a9dd545820fe3317324bc95cc0955f73607bbfd95fee049 \
    --rpc-url http://127.0.0.1:8545

  # Check operator count
  cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
    "operatorCount(bytes32)" \
    0x3f32666a158724369a9dd545820fe3317324bc95cc0955f73607bbfd95fee049 \
    --rpc-url http://127.0.0.1:8545

  # Check if first operator is registered
  cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
    "isOperator(bytes32,address)" \
    0x3f32666a158724369a9dd545820fe3317324bc95cc0955f73607bbfd95fee049 \
    0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
    --rpc-url http://127.0.0.1:8545

  # Try to get latest price (should fail with NoData since no submissions yet)
  cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
    "latestRoundData(bytes32)" \
    0x3f32666a158724369a9dd545820fe3317324bc95cc0955f73607bbfd95fee049 \
    --rpc-url http://127.0.0.1:8545

  3. Deploy Test Consumer (Optional)

  Deploy a simple consumer contract to read from the adapter:

  # Set adapter address
  export ADAPTER=0xD9164F568A7d21189F61bd53502BdE277883A0A2

  # Deploy consumer
  forge script script/DeployTestConsumer.s.sol:DeployTestConsumer \
    --rpc-url http://127.0.0.1:8545 \
    --chain-id 31337 \
    --broadcast \
    -vvv

  4. Start Operator Bot (Submit Price Data)

  Now let's start the operator bot to submit prices:

  # Install dependencies (if not already)
  npm install ethers@6

  # Start the bot (it will submit prices every 30 seconds)
  node scripts/bot/operators-bot.js \
    --rpc http://127.0.0.1:8545 \
    --oracle 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
    --feedDesc "ar/bytes-testv1" \
    --interval 30000

  Expected Output:
  🚀 Operator bot starting
     rpc=http://127.0.0.1:8545 oracle=0x5FbD...0aa3 feed=ar/bytes-testv1 (0x3f32...e049) ops=5 interval=30000ms
  📤 Submitting round 1 for ar/bytes-testv1
    ✍️  0xf39F...2266 → 10050000000  ✅  0x1234...abcd
    ✍️  0x7099...79C8 → 10060000000  ✅  0x5678...efgh
    ✍️  0x3C44...93BC → 10070000000  ✅  0x9abc...ijkl
    ✍️   0x90F7...b906 → 10080000000  ✅  0xdef0...mnop
    ✍️  0x15d3...6A65 → 10090000000  ✅  0x1111...qrst
  🟢 latest round=1 answer=10070000000 age=0s changed=🔄

  5. Monitor Submissions (In Another Terminal)

  Watch the blockchain for oracle events:

  # Watch for RoundFinalized events
  cast logs \
    --address 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
    --from-block latest \
    --rpc-url http://127.0.0.1:8545

  # Or use a more specific event filter
  cast logs \
    --address 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
    "RoundFinalized(bytes32,uint80,uint8)" \
    --from-block 1 \
    --rpc-url http://127.0.0.1:8545

  6. Query Latest Price After Submissions

  After the bot has submitted (wait ~30 seconds), check the price:

  # Direct oracle query
  cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
    "getLatestPrice(bytes32)" \
    0x3f32666a158724369a9dd545820fe3317324bc95cc0955f73607bbfd95fee049 \
    --rpc-url http://127.0.0.1:8545

  # Via Chainlink adapter
  cast call 0xD9164F568A7d21189F61bd53502BdE277883A0A2 \
    "latestRoundData()" \
    --rpc-url http://127.0.0.1:8545

  # Decode the response
  cast --to-dec <returned_hex_value>

  7. Use Makefile Commands (Convenience Wrappers)

  Your Makefile has several useful targets:

  # Set environment variables
  export ORACLE=0x5FbDB2315678afecb367f032d93F642f64180aa3
  export FACTORY=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
  export FEEDS_FILE=feeds/feeds-anvil.json

  # Poke feeds (trigger timeout finalization if needed)
  make anvil-poke-feeds-json

  # Create additional feeds (if you add to feeds-anvil.json)
  make anvil-create-feeds-json

  # Deploy more adapters
  make anvil-deploy-adapters-json

  8. Testing Specific Scenarios

  A. Test Timeout Finalization

  # Submit only 2 out of 5 operators (below max but above min quorum of 3)
  # Wait for timeout (120 seconds based on your config)
  # Then call poke

  cast send 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
    "poke(bytes32)" \
    0x3f32666a158724369a9dd545820fe3317324bc95cc0955f73607bbfd95fee049 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --rpc-url http://127.0.0.1:8545

  B. Test Staleness Check

  # Check if price is stale (0 seconds threshold = any age is stale)
  cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
    "isStale(bytes32,uint256)" \
    0x3f32666a158724369a9dd545820fe3317324bc95cc0955f73607bbfd95fee049 \
    0 \
    --rpc-url http://127.0.0.1:8545

  C. Test Adapter Functions

  # Get decimals
  cast call 0xD9164F568A7d21189F61bd53502BdE277883A0A2 \
    "decimals()" \
    --rpc-url http://127.0.0.1:8545

  # Get description
  cast call 0xD9164F568A7d21189F61bd53502BdE277883A0A2 \
    "description()" \
    --rpc-url http://127.0.0.1:8545

  9. Advanced: Manual Price Submission

  If you want to manually submit a signed price (without the bot):

  # This requires signing an EIP-712 message
  # Easier to use the bot, but here's a JavaScript example:

  cat > submit-price.js << 'EOF'
  import { ethers } from "ethers";

  const provider = new ethers.JsonRpcProvider("http://127.0.0.1:8545");
  const signer = new ethers.Wallet("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", provider);

  const ORACLE = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
  const FEED_ID = "0x3f32666a158724369a9dd545820fe3317324bc95cc0955f73607bbfd95fee049";

  const domain = {
    name: "Price Loom",
    version: "1",
    chainId: 31337,
    verifyingContract: ORACLE,
  };

  const types = {
    PriceSubmission: [
      { name: "feedId", type: "bytes32" },
      { name: "roundId", type: "uint80" },
      { name: "answer", type: "int256" },
      { name: "validUntil", type: "uint256" },
    ],
  };

  const submission = {
    feedId: FEED_ID,
    roundId: 1,
    answer: BigInt(100e8), // 100 with 8 decimals
    validUntil: BigInt(Math.floor(Date.now() / 1000) + 600),
  };

  const signature = await signer.signTypedData(domain, types, submission);
  console.log("Signature:", signature);

  // Submit
  const oracle = new ethers.Contract(ORACLE, [
    "function submitSigned(bytes32,tuple(bytes32,uint80,int256,uint256),bytes)"
  ], signer);

  const tx = await oracle.submitSigned(FEED_ID, submission, signature);
  await tx.wait();
  console.log("Submitted! TX:", tx.hash);
  EOF

  node submit-price.js

  10. Stop Everything

  When you're done testing:

  # Stop the operator bot (Ctrl+C in the bot terminal)

  # Or if running in background:
  pkill -f "operators-bot.js"

  # Stop Anvil (Ctrl+C in the Anvil terminal)

  ---
  📊 Expected Workflow

  Here's the typical testing flow:

  graph TD
      A[Deploy Oracle & Adapter] --> B[Start Operator Bot]
      B --> C[Bot Submits Prices Every 30s]
      C --> D[Oracle Finalizes Rounds]
      D --> E[Query Latest Price]
      E --> F{Price Updated?}
      F -->|Yes| G[Success! Monitor Events]
      F -->|No| H[Check Bot Logs]
      H --> C

  ---
  🔍 Troubleshooting

  Issue: "NoData" error when querying price

  Solution: Wait for the operator bot to submit at least 3 signatures (minSubmissions)

  Issue: Bot not submitting

  Solution: Check:
  1. Anvil is running on port 8545
  2. Bot has correct oracle address
  3. Private keys are correct (should be default Anvil keys)

  Issue: Submissions rejected

  Solution: Check:
  1. Round ID matches (use nextRoundId() to get correct round)
  2. Price is within bounds (0 to 1e22)
  3. Signature is valid and not expired

  ---
  📚 Additional Commands

  # Get next round ID operators should sign
  cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
    "nextRoundId(bytes32)" \
    0x3f32666a158724369a9dd545820fe3317324bc95cc0955f73607bbfd95fee049 \
    --rpc-url http://127.0.0.1:8545

  # Check if new round is due
  cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
    "dueToStart(bytes32,int256)" \
    0x3f32666a158724369a9dd545820fe3317324bc95cc0955f73607bbfd95fee049 \
    10000000000 \
    --rpc-url http://127.0.0.1:8545

  Let me know which test you'd like to run first, or if you encounter any issues! 🚀