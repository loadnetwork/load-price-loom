// Simple operator bot for local anvil demo (ethers v6)
// Usage:
//   node scripts/bot/operators-bot.js \
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
const NUM_OPS = Number(argv.ops || process.env.NUM_OPS || 5);

if (!ORACLE) {
  console.error("Missing --oracle");
  process.exit(1);
}

const provider = new ethers.JsonRpcProvider(RPC);

// Default Anvil private keys (first 5)
const ANVIL_KEYS = [
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
  "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
  "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007dc",
  "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733fe8e2a5f85f38a16",
];

const KEYS = (process.env.PRIVATE_KEYS_JSON ? JSON.parse(process.env.PRIVATE_KEYS_JSON) : ANVIL_KEYS).slice(0, NUM_OPS);

const oracleAbi = [
  "function submitSigned(bytes32, (bytes32,uint80,int256,uint256), bytes)",
  "function nextRoundId(bytes32) view returns (uint80)",
  "function dueToStart(bytes32,int256) view returns (bool)",
  "function getConfig(bytes32) view returns (tuple(uint8,uint8,uint8,uint8,uint32,uint32,uint32,int256,int256,string))",
  "function currentRoundId(bytes32) view returns (uint80)",
  "function latestFinalizedRoundId(bytes32) view returns (uint80)",
  "function latestRoundData(bytes32) view returns (uint80,int256,uint256,uint256,uint80)",
  "function isStale(bytes32,uint256) view returns (bool)",
];

const oracle = new ethers.Contract(ORACLE, oracleAbi, provider);

// random walk price generator around base
let base = 100n * 10n ** 8n; // 100e8
function genPrice(i) {
  // +- 1% variation, operator-indexed
  const drift = BigInt((Math.floor(Math.random() * 200) - 100));
  return base + (base * drift) / 10000n + BigInt(i) * 10n; // slight spread between ops
}

let lastAnswer = null;

async function tick() {
  const round = await oracle.nextRoundId(FEED_ID);
  const proposed = genPrice(0);
  const due = await oracle.dueToStart(FEED_ID, proposed);
  const current = await oracle.currentRoundId(FEED_ID);
  const latest = await oracle.latestFinalizedRoundId(FEED_ID);
  const hasOpen = current > latest;
  if (!hasOpen && !due) {
    console.log("🕒 Not due yet (no open round). Waiting…");
    return;
  }

  console.log(`📤 Submitting round ${round} for ${FEED_DESC}`);
  let idx = 0;
  for (const key of KEYS) {
    const signer = new ethers.Wallet(key, provider);

    const answer = genPrice(idx++);
    const validUntil = BigInt(Math.floor(Date.now() / 1000) + 60);
    const submission = { feedId: FEED_ID, roundId: round, answer, validUntil };

    const domain = {
      name: "Price Loom",
      version: "1",
      chainId: (await provider.getNetwork()).chainId,
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

    const signature = await signer.signTypedData(domain, types, submission);
    const tx = await oracle.connect(signer).submitSigned(FEED_ID, submission, signature);
    await tx.wait();
    const short = (s) => (typeof s === 'string' && s.startsWith('0x') ? `${s.slice(0, 6)}…${s.slice(-4)}` : s);
    console.log(`  ✍️  ${short(signer.address)} → ${answer.toString()}  ✅ ${short(tx.hash)}`);
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
}

const short = (s) => (typeof s === 'string' && s.startsWith('0x') ? `${s.slice(0, 6)}…${s.slice(-4)}` : s);
console.log(`🚀 Operator bot starting`);
console.log(`   rpc=${RPC} oracle=${short(ORACLE)} feed=${FEED_DESC} (${FEED_ID}) ops=${NUM_OPS} interval=${INTERVAL}ms`);
await tick();
setInterval(tick, INTERVAL);
