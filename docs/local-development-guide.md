# Local Development Guide

Complete guide for developing and testing Price Loom Oracle locally using Foundry and Anvil.

---

## Table of Contents

1. [Quick Start (5 Minutes)](#quick-start-5-minutes)
2. [Environment Setup](#environment-setup)
3. [Testing Workflows](#testing-workflows)
4. [Common Development Tasks](#common-development-tasks)
5. [Debugging Tips](#debugging-tips)
6. [Foundry Commands Reference](#foundry-commands-reference)

---

## Quick Start (5 Minutes)

Get a full oracle system running locally in 3 terminals:

### Terminal 1: Start Anvil

```bash
# Start local Ethereum node
anvil
```

**Expected Output:**
```
                             _   _
                            (_) | |
      __ _   _ __   __   __  _  | |
     / _` | | '_ \  \ \ / / | | | |
    | (_| | | | | |  \ V /  | | | |
     \__,_| |_| |_|   \_/   |_| |_|

    0.2.0 (aaa111b 2024-01-01T00:00:00.000000000Z)

Available Accounts
==================
(0) 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000.000000000000000000 ETH)
(1) 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 (10000.000000000000000000 ETH)
...

Listening on 127.0.0.1:8545
```

### Terminal 2: Deploy & Run Bot

```bash
# Deploy everything (oracle + factory + feeds + adapters)
make anvil-bootstrap-all

# Copy oracle address from output, then start bot
export ORACLE=0x5FbDB2315678afecb367f032d93F642f64180aa3
node scripts/bot/operators-bot.mjs \
  --rpc http://127.0.0.1:8545 \
  --oracle $ORACLE \
  --feedDesc "ar/bytes-testv1" \
  --interval 30000
```

**Expected Output:**
```
✅ Oracle deployed: 0x5FbDB2315678afecb367f032d93F642f64180aa3
✅ Factory deployed: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
✅ Feed created: ar/bytes-testv1
✅ Adapter deployed: 0xD9164F568A7d21189F61bd53502BdE277883A0A2

🚀 Operator bot starting
📤 Starting new round 1 for ar/bytes-testv1
  ✍️  0xf39F…2266 → 9923000000  ✅
  ✅ Quorum (3) reached
🟢 latest round=1 answer=9981000020 age=1s
```

### Terminal 3: Test & Interact

```bash
# Deploy test consumer
export ADAPTER=0xD9164F568A7d21189F61bd53502BdE277883A0A2
forge script script/DeployTestConsumer.s.sol:DeployTestConsumer \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast

# Run integration test
export CONSUMER=0x610178dA211FEF7D417bC0e6FeD39F05609AD788
node scripts/test-adapter-consumer.mjs
```

**Expected Output:**
```
✅ ALL TESTS PASSED!
```

🎉 **You now have a fully functional oracle system running locally!**

---

## Environment Setup

### 1. Install Prerequisites

```bash
# Install Foundry (includes forge, cast, anvil)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install Node.js (for operator bot and test scripts)
# On macOS:
brew install node

# On Linux:
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
```

### 2. Clone and Setup Repository

```bash
# Clone repository
git clone https://github.com/your-org/load-price-loom
cd load-price-loom

# Install Solidity dependencies
git submodule update --init --recursive
forge install

# Install Node.js dependencies
npm install

# Build contracts
forge build
```

**Expected Output:**
```
[⠊] Compiling...
[⠒] Compiling 45 files with 0.8.20
[⠢] Solc 0.8.20 finished in 3.21s
Compiler run successful!
```

### 3. Verify Installation

```bash
# Run tests
forge test

# Check Anvil
anvil --version

# Check Node scripts can load
node --version
npm list ethers
```

**Expected Output:**
```
forge test: ✅ All tests passed
anvil: 0.2.0
node: v20.x.x
ethers: 6.13.2
```

---

## Testing Workflows

### Unit Tests (Forge)

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path test/PriceLoomOracle.t.sol

# Run specific test function
forge test --match-test testSubmitSigned

# Run with verbosity (shows console.log output)
forge test -vvv

# Run with gas report
forge test --gas-report

# Run with coverage
forge coverage
```

**Example Output:**
```
Running 42 tests for test/PriceLoomOracle.t.sol:PriceLoomOracleTest
[PASS] testSubmitSigned() (gas: 123456)
[PASS] testMedianCalculation() (gas: 98765)
[PASS] testPauseUnpause() (gas: 45678)
...
Test result: ok. 42 passed; 0 failed; 0 skipped; finished in 2.34s
```

### Integration Tests (Local Anvil)

#### Full Stack Test

```bash
# Terminal 1: Start Anvil
anvil

# Terminal 2: Deploy and run bot
make anvil-bootstrap-all
export ORACLE=0x5FbDB...
export ADAPTER=0xD916...
node scripts/bot/operators-bot.mjs --rpc http://127.0.0.1:8545 --oracle $ORACLE --feedDesc "ar/bytes-testv1" --interval 30000

# Terminal 3: Wait 1 minute for rounds, then test
sleep 60
export CONSUMER=0x6101...
node scripts/test-adapter-consumer.mjs
```

#### Single Contract Interaction Test

```bash
# Start Anvil
anvil &

# Deploy oracle only
forge create src/PriceLoomOracle.sol:PriceLoomOracle \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --constructor-args 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

# Interact with it
export ORACLE=0x5FbDB2315678afecb367f032d93F642f64180aa3
export FEED_ID=$(cast keccak "test-feed")

# Create a feed
cast send $ORACLE "createFeed(bytes32,(uint8,uint8,uint8,uint8,uint32,uint32,uint32,int256,int256,string),address[])" \
  $FEED_ID "(8,2,3,0,3600,50,900,0,1000000000000000000000,'Test Feed')" "[0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266]" \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Read feed config
cast call $ORACLE "getConfig(bytes32)" $FEED_ID --rpc-url http://127.0.0.1:8545
```

**Expected Output:**
```
Deployed to: 0x5FbDB2315678afecb367f032d93F642f64180aa3
✅ Feed created
0x0000000000000000000000000000000000000000000000000000000000000008  # decimals: 8
```

---

## Common Development Tasks

### Task 1: Test Contract Changes

```bash
# Make changes to contracts
vim src/PriceLoomOracle.sol

# Rebuild
forge build

# Run specific test
forge test --match-test testYourNewFeature -vvv

# If test passes, run full suite
forge test
```

### Task 2: Deploy Updated Contract to Local Anvil

```bash
# Start fresh Anvil
anvil

# In another terminal, deploy with script
forge script script/DeployOracle.s.sol:DeployOracle \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Verify deployment
export ORACLE=0x5FbDB2315678afecb367f032d93F642f64180aa3
cast call $ORACLE "version()(string)" --rpc-url http://127.0.0.1:8545
```

### Task 3: Test Feed Configuration Changes

```bash
# Start Anvil and deploy
anvil &
make anvil-bootstrap-all

# Modify feed config
export ORACLE=0x5FbDB...
export FEED_ID=$(cast keccak "ar/bytes-testv1")

# Pause oracle
cast send $ORACLE "pause()" \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Update config (change heartbeat to 7200)
cast send $ORACLE "setFeedConfig(bytes32,(uint8,uint8,uint8,uint8,uint32,uint32,uint32,int256,int256,string))" \
  $FEED_ID "(8,3,5,0,7200,50,900,0,10000000000000000000000,'AR/byte updated')" \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Verify change
cast call $ORACLE "getConfig(bytes32)" $FEED_ID --rpc-url http://127.0.0.1:8545

# Unpause
cast send $ORACLE "unpause()" \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### Task 4: Test Operator Changes

```bash
# Add a new operator
export NEW_OP=0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65

cast send $ORACLE "addOperator(bytes32,address)" $FEED_ID $NEW_OP \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Verify operator added
cast call $ORACLE "getOperators(bytes32)" $FEED_ID --rpc-url http://127.0.0.1:8545

# Remove operator
cast send $ORACLE "removeOperator(bytes32,address)" $FEED_ID $NEW_OP \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### Task 5: Debug Failed Transaction

```bash
# Run transaction with maximum verbosity
cast send $ORACLE "submitSigned(...)" \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac... \
  --trace

# Or simulate call without broadcasting
cast call $ORACLE "submitSigned(...)" \
  --rpc-url http://127.0.0.1:8545 \
  --from 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

# Get transaction receipt
cast receipt 0xTransactionHash --rpc-url http://127.0.0.1:8545

# Decode revert reason
cast 4byte 0x32e1428f  # Looks up error signature
```

### Task 6: Test Gas Optimization

```bash
# Run tests with gas snapshot
forge test --gas-report

# Generate snapshot file
forge snapshot

# Compare after changes
forge snapshot --diff
```

**Example Output:**
```
╭────────────────────────────────────────────────────────────────────╮
│ PriceLoomOracle contract                                           │
├──────────────────────────────────┬─────────────────┬───────────────┤
│ Function Name                    │ min             │ avg           │
├──────────────────────────────────┼─────────────────┼───────────────┤
│ submitSigned                     │ 85234           │ 92456         │
│ createFeed                       │ 234567          │ 245678        │
│ latestRoundData                  │ 4321            │ 4567          │
╰──────────────────────────────────┴─────────────────┴───────────────╯
```

### Task 7: Fork Mainnet for Testing

```bash
# Fork from Alphanet (requires RPC URL with archive access)
export FORK_URL=https://alphanet.load.network
anvil --fork-url $FORK_URL

# Deploy new contracts on fork
forge script script/DeployOracle.s.sol:DeployOracle \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast

# Interact with existing mainnet contracts + your new contracts
cast call 0xExistingMainnetContract "someFunction()" --rpc-url http://127.0.0.1:8545
```

### Task 8: Reset Anvil State Quickly

```bash
# Instead of restarting Anvil, use snapshots
# In Anvil terminal or via RPC:

# Create snapshot
cast rpc evm_snapshot --rpc-url http://127.0.0.1:8545
# Returns: 0x1

# Do testing...

# Revert to snapshot
cast rpc evm_revert 0x1 --rpc-url http://127.0.0.1:8545

# Or set specific block time
cast rpc evm_setNextBlockTimestamp 1234567890 --rpc-url http://127.0.0.1:8545
cast rpc evm_mine --rpc-url http://127.0.0.1:8545
```

---

## Debugging Tips

### 1. Enable Console Logging in Tests

```solidity
import "forge-std/console.sol";

function testDebug() public {
    console.log("Value:", someValue);
    console.log("Address:", address(contract));
    console.logBytes32(feedId);
}
```

Run with `-vvv`:
```bash
forge test --match-test testDebug -vvv
```

### 2. Trace Transaction Execution

```bash
# Full trace of transaction
cast run 0xTransactionHash --rpc-url http://127.0.0.1:8545 --trace

# Debug specific transaction
cast run 0xTransactionHash --rpc-url http://127.0.0.1:8545 --debug
```

### 3. Decode ABI-Encoded Data

```bash
# Decode function call data
cast 4byte 0xa9059cbb  # transfer(address,uint256)

# Decode specific calldata
cast --calldata-decode "transfer(address,uint256)" 0xa9059cbb000000000000000000000000...

# Decode event logs
cast --abi-decode "event PriceUpdated(bytes32 indexed feedId, uint80 roundId, int256 answer)" 0x...
```

### 4. Inspect Storage Slots

```bash
# Get storage at slot 0
cast storage $ORACLE 0 --rpc-url http://127.0.0.1:8545

# Get specific mapping slot (requires calculation)
# For mapping at slot 5, key = feedId:
cast index bytes32 $FEED_ID 5  # Calculate slot
cast storage $ORACLE 0x... --rpc-url http://127.0.0.1:8545
```

### 5. Check Block State

```bash
# Get current block
cast block-number --rpc-url http://127.0.0.1:8545

# Get block details
cast block latest --rpc-url http://127.0.0.1:8545

# Get account balance
cast balance 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url http://127.0.0.1:8545
```

### 6. Common Error Codes and Fixes

| Error | Meaning | Fix |
|-------|---------|-----|
| `EnforcedPause()` (0xd93c0665) | Oracle paused | Call `unpause()` as pauser |
| `RoundFull()` (0x32e1428f) | Round has maxSubmissions | Wait for next round |
| `NotOperator()` (0x7c214f04) | Not authorized | Add address as operator first |
| `NoData()` (0x...) | Feed has no finalized rounds | Submit prices via operator bot |
| `InvalidConfig()` | Config validation failed | Check min/max submissions, operators count |

### 7. Watch Events in Real-Time

```bash
# In a separate terminal, watch for PriceUpdated events
cast logs \
  --address $ORACLE \
  'PriceUpdated(bytes32 indexed,uint80,int256)' \
  --from-block latest \
  --rpc-url http://127.0.0.1:8545 \
  --subscribe
```

---

## Foundry Commands Reference

### Build & Compile

```bash
forge build                  # Compile contracts
forge build --force          # Force recompile all
forge clean                  # Remove build artifacts
forge fmt                    # Format Solidity code
forge inspect <contract> abi # Output contract ABI
```

### Testing

```bash
forge test                              # Run all tests
forge test -vv                          # Verbose (shows events)
forge test -vvv                         # Very verbose (shows traces)
forge test -vvvv                        # Extremely verbose (shows setup)
forge test --match-test <pattern>       # Run matching tests
forge test --match-contract <pattern>   # Run tests in matching contract
forge test --match-path <path>          # Run tests in file
forge test --gas-report                 # Show gas usage
forge test --debug <test>               # Interactive debugger
forge coverage                          # Generate coverage report
forge snapshot                          # Save gas snapshot
forge snapshot --diff                   # Compare with saved snapshot
```

### Deployment

```bash
forge create <contract> --rpc-url <url> --private-key <key>
forge script <script> --rpc-url <url> --broadcast
forge verify-contract <address> <contract> --chain-id <id> --etherscan-api-key <key>
```

### Cast (Interaction)

```bash
# Calls (read-only)
cast call <contract> <function> [args...] --rpc-url <url>
cast call <contract> "balanceOf(address)(uint256)" 0x... --rpc-url <url>

# Sends (write)
cast send <contract> <function> [args...] --rpc-url <url> --private-key <key>
cast send <contract> "transfer(address,uint256)" 0x... 1000 --rpc-url <url> --private-key <key>

# Utilities
cast keccak <string>                    # Hash string
cast 4byte <selector>                   # Lookup function signature
cast abi-encode <function> [args...]    # Encode function call
cast abi-decode <function> <data>       # Decode function output
cast sig <function>                     # Get function selector

# Chain info
cast block-number --rpc-url <url>
cast balance <address> --rpc-url <url>
cast code <address> --rpc-url <url>
cast storage <address> <slot> --rpc-url <url>

# Transaction info
cast tx <hash> --rpc-url <url>
cast receipt <hash> --rpc-url <url>
cast logs --rpc-url <url>
```

### Anvil (Local Node)

```bash
anvil                           # Start with default settings
anvil --port 8545               # Custom port
anvil --chain-id 31337          # Custom chain ID
anvil --fork-url <url>          # Fork from remote chain
anvil --block-time 1            # Set block time (seconds)
anvil --accounts 20             # Number of test accounts
anvil --mnemonic "<phrase>"     # Custom mnemonic
```

### Chisel (Solidity REPL)

```bash
chisel                          # Start interactive Solidity shell
```

Example session:
```solidity
➜ uint256 x = 42
➜ x * 2
Type: uint256
└ Value: 84
➜ keccak256(abi.encodePacked("test"))
Type: bytes32
└ Value: 0x9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658
```

---

## Quick Troubleshooting

### Problem: "forge: command not found"
**Solution:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Problem: "Error: could not find artifact"
**Solution:**
```bash
forge clean
forge build
```

### Problem: Test fails with "OutOfGas"
**Solution:**
```bash
# Increase gas limit in foundry.toml
[profile.default]
gas_limit = "18446744073709551615"
```

### Problem: Anvil "Address already in use"
**Solution:**
```bash
# Kill existing Anvil
pkill anvil
# Or use different port
anvil --port 8546
```

### Problem: Bot can't connect to Anvil
**Solution:**
```bash
# Check Anvil is running
curl -X POST http://127.0.0.1:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Should return: {"jsonrpc":"2.0","id":1,"result":"0x..."}
```

---

## Next Steps

- **Read the deployment cookbook**: [docs/deployment-cookbook.md](./deployment-cookbook.md)
- **Understand maintenance operations**: [docs/maintenance-guide.md](./maintenance-guide.md)
- **Review operator bot details**: [scripts/README.md](../scripts/README.md)
- **Study the oracle design**: [docs/oracle-design-v0.md](./oracle-design-v0.md)

Happy developing! 🚀
