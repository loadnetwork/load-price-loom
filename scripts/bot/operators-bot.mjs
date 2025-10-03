// Simple operator bot for local anvil demo (ethers v6)
// Usage:
//   node scripts/bot/operators-bot.mjs \
//     --rpc http://127.0.0.1:8545 \
//     --oracle 0xOracle \
//     --feedDesc "ar/bytes-testv1" \
//     --interval 30000

import { ethers } from "ethers";
import { keccak256, toUtf8Bytes } from "ethers";

const argv = Object.fromEntries(process.argv.slice(2).map((x, i, arr) => {
  if (x.startsWith("--")) return [x.slice(2), arr[i + 1]];
  return [];
}).filter(Boolean));

const RPC = argv.rpc || process.env.RPC_URL || "http://127.0.0.1:8545";
const ORACLE = argv.oracle || process.env.ORACLE;
const FEED_DESC = argv.feedDesc || process.env.FEED_DESC || "ar/bytes-testv1";
const FEED_ID = argv.feedId || process.env.FEED_ID || keccak256(toUtf8Bytes(FEED_DESC));
const INTERVAL = Number(argv.interval || process.env.INTERVAL_MS || 30000);
const NUM_OPS = Number(argv.ops || process.env.NUM_OPS || 6);
const PRICE_BASE = Number(argv.priceBase || process.env.PRICE_BASE || 6); // base price defaults to AR/usd, AR per byte is around 0.00000000199 AR (1.99e-9?)

if (!ORACLE) {
  console.error("Missing --oracle");
  process.exit(1);
}

const provider = new ethers.JsonRpcProvider(RPC);

// Default Anvil private keys (matching feeds-anvil.json operators)
const ANVIL_KEYS = [
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",  // 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",  // 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
  "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",  // 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
  "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",  // 0x90F79bf6EB2c4f870365E785982E1f101E93b906
  "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a",  // 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65
  "0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba",  // 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc
];

let KEYS = (process.env.PRIVATE_KEYS_JSON ? JSON.parse(process.env.PRIVATE_KEYS_JSON) : ANVIL_KEYS).slice(0, NUM_OPS);

const oracleAbi = [
  "function submitSigned(bytes32 feedId, tuple(bytes32 feedId, uint80 roundId, int256 answer, uint256 validUntil) sub, bytes sig)",
  "function nextRoundId(bytes32) view returns (uint80)",
  "function dueToStart(bytes32,int256) view returns (bool)",
  "function getConfig(bytes32) view returns (tuple(uint8,uint8,uint8,uint8,uint32,uint32,uint32,int256,int256,string))",
  "function currentRoundId(bytes32) view returns (uint80)",
  "function latestFinalizedRoundId(bytes32) view returns (uint80)",
  "function latestRoundData(bytes32) view returns (uint80,int256,uint256,uint256,uint80)",
  "function isStale(bytes32,uint256) view returns (bool)",
  "function poke(bytes32) returns (bool)",
  "function getRoundData(bytes32,uint80) view returns (uint80,int256,uint256,uint256,uint80)",
  "function paused() view returns (bool)",
  "function getOperators(bytes32) view returns (address[])",
];

const oracle = new ethers.Contract(ORACLE, oracleAbi, provider);

// Price generator - base will be set after reading decimals from oracle config
let base = 0n;
let decimals = 8; // Will be updated from oracle config

function genPrice(i) {
  // +- 1% variation, operator-indexed
  const drift = BigInt((Math.floor(Math.random() * 200) - 100));
  return base + (base * drift) / 10000n + BigInt(i) * 10n; // slight spread between ops
}

async function initOperators(oracle, feedId) {
  const onchainOps = await oracle.getOperators(feedId);
  if (!onchainOps || onchainOps.length === 0) {
    throw new Error("No operators found on-chain for this feed.");
  }

  // Create a lookup map of address -> private key for the known test keys
  const addressToKey = new Map();
  for (const key of ANVIL_KEYS) {
    const wallet = new ethers.Wallet(key);
    addressToKey.set(wallet.address.toLowerCase(), key);
  }

  // Create wallets only for the operators that are actually on-chain
  const wallets = onchainOps.map(opAddress => {
    const privateKey = addressToKey.get(opAddress.toLowerCase());
    if (!privateKey) {
      console.warn(`⚠️  Could not find private key for registered operator ${opAddress}. Skipping.`);
      return null;
    }
    return new ethers.Wallet(privateKey, provider);
  }).filter(Boolean); // filter out nulls

  if (wallets.length !== onchainOps.length) {
    console.warn("Warning: Not all on-chain operators could be initialized. The bot will run with a subset.");
  }

  if (wallets.length === 0) {
    throw new Error("Could not initialize any operator wallets. Check that feeds.json operators match local anvil keys.");
  }

  // Overwrite the global KEYS array so the main loop uses the correct signers.
  const newKeys = wallets.map(w => w.privateKey);
  KEYS.splice(0, KEYS.length, ...newKeys);

  console.log(`✅ Initialized ${wallets.length}/${onchainOps.length} valid operator wallets`);

  return wallets;
}

let lastAnswer = null;
let consecutiveFailures = 0;

const short = (s) => (typeof s === 'string' && s.startsWith('0x') ? `${s.slice(0, 6)}…${s.slice(-4)}` : s);

async function tick() {
  try {
    // Check if oracle is paused
    const isPaused = await oracle.paused();
    if (isPaused) {
      console.log("⏸️  Oracle is paused. Waiting for unpause...");
      return;
    }

    // Fetch config for min/max
    const cfg = await oracle.getConfig(FEED_ID);
    const minSubs = Number(cfg.minSubmissions);
    const maxSubs = Number(cfg.maxSubmissions);

    // Use nextRoundId - it tells us which round to submit for
    let targetRound = await oracle.nextRoundId(FEED_ID);
    const latest = await oracle.latestFinalizedRoundId(FEED_ID);
    const isNewRound = targetRound > latest;

    // Recovery mechanism: detect stuck round (has submissions but not finalizing)
    if (consecutiveFailures >= 2) {
      console.log(`🔧 Detected potential issue. Attempting poke() to force timeout handling...`);
      try {
        // Use first operator's signer for poke()
        const signer = new ethers.Wallet(KEYS[0], provider);
        const tx = await oracle.connect(signer).poke(FEED_ID);
        await tx.wait();
        console.log(`  ✅ poke() succeeded - oracle state updated`);
        consecutiveFailures = 0;
        return;
      } catch (err) {
        console.log(`  ℹ️  poke() returned: ${err.shortMessage || err.message}`);
      }
    }

    if (isNewRound) {
      // Starting a new round - check if it's due
      const proposed = genPrice(0);
      const due = await oracle.dueToStart(FEED_ID, proposed);

      if (!due) {
        console.log("🕒 Not due yet (no open round). Waiting…");
        return;
      }
      console.log(`📤 Starting new round ${targetRound} for ${FEED_DESC}`);
    } else {
      // Continuing existing open round
      console.log(`📤 Submitting to open round ${targetRound} for ${FEED_DESC}`);
    }

    // Prepare domain for EIP-712 (same for all operators) - cache chainId
    const chainId = (await provider.getNetwork()).chainId;
    const domain = {
      name: "Price Loom",
      version: "1",
      chainId: chainId,
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

    // Submit operators SEQUENTIALLY to avoid races
    let successful = 0;
    for (let idx = 0; idx < KEYS.length; idx++) {
      // Early exit if quorum reached
      if (successful >= minSubs) {
        console.log(`  ✅ Quorum (${minSubs}) reached—skipping remaining operators`);
        break;
      }

      const key = KEYS[idx];
      const signer = new ethers.Wallet(key, provider);
      let answer = genPrice(idx);
      let validUntil = BigInt(Math.floor(Date.now() / 1000) + 60);

      // Re-query round before each (adapts if closed mid-loop)
      const currentTargetRound = await oracle.nextRoundId(FEED_ID);
      if (currentTargetRound !== targetRound) {
        console.log(`  ℹ️  Round advanced to ${currentTargetRound} mid-submission—skipping`);
        break;
      }

      const submission = {
        feedId: FEED_ID,
        roundId: currentTargetRound,
        answer,
        validUntil
      };

      const signature = await signer.signTypedData(domain, types, submission);

      try {
        const tx = await oracle.connect(signer).submitSigned(FEED_ID, submission, signature);
        await tx.wait();
        console.log(`  ✍️  ${short(signer.address)} → ${answer.toString()}  ✅ ${short(tx.hash)}`);
        successful++;

        // Delay to let finalize settle if quorum hit
        await new Promise(r => setTimeout(r, 300));
      } catch (err) {
        // Enhanced error parsing
        let errorData = '';
        let errCode = 'unknown';

        if (err.data && typeof err.data === 'string' && err.data.startsWith('0x')) {
          errorData = err.data;
          const match = err.data.match(/^0x[0-9a-f]{8}/i);
          if (match) errCode = match[0];
        } else if (err.error?.data && typeof err.error.data === 'string') {
          errorData = err.error.data;
          const match = err.error.data.match(/^0x[0-9a-f]{8}/i);
          if (match) errCode = match[0];
        } else if (err.receipt?.logs?.[0]?.data) {
          errorData = err.receipt.logs[0].data;
          const match = errorData.match(/0x[0-9a-f]{8}/i);
          if (match) errCode = match[0];
        }

        const shortAddr = short(signer.address);
        const msg = err.shortMessage || err.reason || err.message || '';
        const shortMsg = msg.length > 50 ? msg.slice(0, 47) + '...' : msg;

        if (errCode === '0x32e1428f' || errorData.includes('0x32e1428f')) { // RoundFull
          console.log(`  ⏭️  ${shortAddr} skipped (round full)`);
        } else if (errCode === '0x8daa9e49' || errorData.includes('0x8daa9e49')) { // DuplicateSubmission
          console.log(`  ⏭️  ${shortAddr} skipped (already submitted)`);
        } else if (errCode === '0xc3fa7054' || errorData.includes('0xc3fa7054')) { // WrongRound
          console.log(`  ⏭️  ${shortAddr} skipped (wrong round)`);
        } else if (errCode === '0x47a2375f' || errorData.includes('0x47a2375f')) { // NotDue
          console.log(`  ⏭️  ${shortAddr} skipped (not due)`);
        } else if (errCode === '0xd93c0665' || errorData.includes('0xd93c0665')) { // EnforcedPause
          console.log(`  ⏸️  ${shortAddr} skipped (oracle paused)`);
        } else if (errCode === '0x7c214f04' || errorData.includes('0x7c214f04')) { // NotOperator
          console.log(`  ❌ ${shortAddr} skipped (not an operator)`);
        } else {
          console.log(`  ❌ ${shortAddr} failed: ${errCode} (${shortMsg})`);
        }
      }
    }

    console.log(`  📊 ${successful}/${KEYS.length} operators submitted successfully`);

    // Track consecutive failures for recovery logic
    if (successful === 0) {
      consecutiveFailures++;
    } else {
      consecutiveFailures = 0;
    }

    // Verify latest data freshness and change
    try {
      await new Promise(r => setTimeout(r, 1000));
      const [rid, ans, , updatedAt] = await oracle.latestRoundData(FEED_ID);
      const now = BigInt(Math.floor(Date.now() / 1000));
      const age = now - BigInt(updatedAt);
      const stale = await oracle.isStale(FEED_ID, 0);
      const changed = lastAnswer === null ? true : (BigInt(ans) !== BigInt(lastAnswer));
      const freshEmoji = stale ? '⚠️' : '🟢';
      const changeEmoji = changed ? '🔄' : '⏸️';
      console.log(`${freshEmoji} latest round=${rid} answer=${ans.toString()} age=${age}s changed=${changeEmoji}`);
      lastAnswer = BigInt(ans);
    } catch (e) {
      console.warn("ℹ️  Could not read latestRoundData yet:", e.message || e);
    }
  } catch (error) {
    console.error("❌ Tick failed:", error.shortMessage || error.message);
  }
}

console.log(`🚀 Operator bot starting`);
console.log(`   rpc=${RPC} oracle=${short(ORACLE)} feed=${FEED_DESC} (${FEED_ID}) ops=${NUM_OPS} interval=${INTERVAL}ms`);

// Read feed config from oracle to get decimals
// Config tuple: [decimals, minSubs, maxSubs, trim, heartbeat, deviation, timeout, minPrice, maxPrice, description]
const cfg = await oracle.getConfig(FEED_ID);
decimals = Number(cfg[0]); // decimals is the first field

// Calculate base price scaled to the feed's decimals
// For AR/byte (1.5e-9) with 18 decimals: 1.5e-9 * 1e18 = 1.5e9
// For AR/USD (6) with 8 decimals: 6 * 1e8 = 6e8
const scaledPrice = PRICE_BASE * Math.pow(10, decimals);
base = BigInt(Math.floor(scaledPrice));

console.log(`   📊 Feed: ${cfg[9]} (decimals=${decimals})`);
console.log(`   💰 Base price: ${PRICE_BASE} → ${base} (scaled to ${decimals} decimals)`);

// Initialize operators before starting
await initOperators(oracle, FEED_ID);

await tick();
setInterval(tick, INTERVAL);
