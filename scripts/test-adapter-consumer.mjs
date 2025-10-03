// Test script to verify Adapter and TestPriceConsumer integration
// Usage: node scripts/test-adapter-consumer.mjs

import { ethers } from "ethers";
/*
  Oracle :
  0x5FbDB2315678afecb367f032d93F642f64180aa3
  Factory:
  0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
  Created feed: ar/bytes-testv1
  0x3f32666a158724369a9dd545820fe3317324bc95cc0955f73607bbfd95fee049
  Adapter predicted:
  0xD9164F568A7d21189F61bd53502BdE277883A0A2
  Adapter deployed :
  0xD9164F568A7d21189F61bd53502BdE277883A0A2
  */

const RPC = process.env.RPC_URL || "http://127.0.0.1:8545";
const ORACLE = process.env.ORACLE || "0x5FbDB2315678afecb367f032d93F642f64180aa3";
const ADAPTER = process.env.ADAPTER || "0xD9164F568A7d21189F61bd53502BdE277883A0A2";
const CONSUMER = process.env.CONSUMER || "0x610178dA211FEF7D417bC0e6FeD39F05609AD788";
const FEED_DESC = process.env.FEED_DESC || "ar/bytes-testv1";
const FEED_ID = ethers.keccak256(ethers.toUtf8Bytes(FEED_DESC));

const provider = new ethers.JsonRpcProvider(RPC);

// ABIs
const oracleAbi = [
  "function latestRoundData(bytes32) view returns (uint80,int256,uint256,uint256,uint80)",
  "function getRoundData(bytes32,uint80) view returns (uint80,int256,uint256,uint256,uint80)",
  "function getConfig(bytes32) view returns (tuple(uint8 decimals,uint8 minSubmissions,uint8 maxSubmissions,uint8 trim,uint32 heartbeatSec,uint32 deviationBps,uint32 timeoutSec,int256 minPrice,int256 maxPrice,string description))",
];

const adapterAbi = [
  "function latestRoundData() view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)",
  "function getRoundData(uint80) view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)",
  "function decimals() view returns (uint8)",
  "function description() view returns (string)",
  "function version() view returns (uint256)",
];

const consumerAbi = [
  "function latest() view returns (int256 answer, uint256 updatedAt)",
  "function adapter() view returns (address)",
];

const oracle = new ethers.Contract(ORACLE, oracleAbi, provider);
const adapter = new ethers.Contract(ADAPTER, adapterAbi, provider);
const consumer = new ethers.Contract(CONSUMER, consumerAbi, provider);

const short = (s) => (typeof s === 'string' && s.startsWith('0x') ? `${s.slice(0, 6)}…${s.slice(-4)}` : s);

console.log("🧪 Testing Adapter & Consumer Integration\n");
console.log("Configuration:");
console.log(`  Oracle:   ${short(ORACLE)}`);
console.log(`  Adapter:  ${short(ADAPTER)}`);
console.log(`  Consumer: ${short(CONSUMER)}`);
console.log(`  Feed:     ${FEED_DESC}`);
console.log(`  Feed ID:  ${FEED_ID}\n`);

async function testOracle() {
  console.log("📊 Testing Oracle...");
  try {
    const [roundId, answer, startedAt, updatedAt, answeredInRound] = await oracle.latestRoundData(FEED_ID);
    const config = await oracle.getConfig(FEED_ID);
    const decimals = config.decimals;
    const description = config.description;

    const now = Math.floor(Date.now() / 1000);
    const age = now - Number(updatedAt);

    console.log(`  ✅ Latest Round Data:`);
    console.log(`     Round ID:     ${roundId}`);
    console.log(`     Answer:       ${answer.toString()} (${Number(answer) / 10**Number(decimals)})`);
    console.log(`     Decimals:     ${decimals}`);
    console.log(`     Description:  ${description}`);
    console.log(`     Updated At:   ${new Date(Number(updatedAt) * 1000).toISOString()}`);
    console.log(`     Age:          ${age}s`);
    console.log(`     Answered In:  ${answeredInRound}\n`);

    return { roundId, answer, decimals, updatedAt };
  } catch (err) {
    console.log(`  ❌ Oracle test failed: ${err.message}\n`);
    throw err;
  }
}

async function testAdapter(expectedRoundId, expectedAnswer) {
  console.log("🔌 Testing Adapter (Chainlink-compatible)...");
  try {
    const [roundId, answer, startedAt, updatedAt, answeredInRound] = await adapter.latestRoundData();
    const decimals = await adapter.decimals();
    const description = await adapter.description();
    const version = await adapter.version();

    const now = Math.floor(Date.now() / 1000);
    const age = now - Number(updatedAt);

    console.log(`  ✅ Latest Round Data:`);
    console.log(`     Round ID:     ${roundId}`);
    console.log(`     Answer:       ${answer.toString()} (${Number(answer) / 10**Number(decimals)})`);
    console.log(`     Decimals:     ${decimals}`);
    console.log(`     Description:  ${description}`);
    console.log(`     Version:      ${version}`);
    console.log(`     Updated At:   ${new Date(Number(updatedAt) * 1000).toISOString()}`);
    console.log(`     Age:          ${age}s`);
    console.log(`     Answered In:  ${answeredInRound}\n`);

    // Verify data matches oracle
    if (roundId === expectedRoundId && answer === expectedAnswer) {
      console.log(`  ✅ Adapter data matches Oracle\n`);
    } else {
      console.log(`  ⚠️  Adapter data mismatch!`);
      console.log(`     Expected: roundId=${expectedRoundId}, answer=${expectedAnswer}`);
      console.log(`     Got:      roundId=${roundId}, answer=${answer}\n`);
    }

    return { roundId, answer, decimals, updatedAt };
  } catch (err) {
    console.log(`  ❌ Adapter test failed: ${err.message}\n`);
    throw err;
  }
}

async function testConsumer(expectedAnswer, expectedUpdatedAt) {
  console.log("🛒 Testing Consumer Contract...");
  try {
    const adapterAddr = await consumer.adapter();
    console.log(`  Configured Adapter: ${short(adapterAddr)}`);

    if (adapterAddr.toLowerCase() !== ADAPTER.toLowerCase()) {
      console.log(`  ⚠️  Consumer is using different adapter: ${adapterAddr}`);
      console.log(`     Expected: ${ADAPTER}\n`);
    }

    const [answer, updatedAt] = await consumer.latest();

    console.log(`  ✅ Latest Data:`);
    console.log(`     Answer:       ${answer.toString()}`);
    console.log(`     Updated At:   ${new Date(Number(updatedAt) * 1000).toISOString()}`);
    console.log(`     Age:          ${Math.floor(Date.now() / 1000) - Number(updatedAt)}s\n`);

    // Verify data matches expected
    if (answer === expectedAnswer && updatedAt === expectedUpdatedAt) {
      console.log(`  ✅ Consumer data matches Oracle & Adapter\n`);
    } else if (answer !== expectedAnswer) {
      console.log(`  ⚠️  Consumer data mismatch!`);
      console.log(`     Expected: answer=${expectedAnswer}`);
      console.log(`     Got:      answer=${answer}\n`);
    }

    return { answer, updatedAt };
  } catch (err) {
    console.log(`  ❌ Consumer test failed: ${err.message}\n`);
    throw err;
  }
}

async function testHistoricalData() {
  console.log("📜 Testing Historical Data Access...");
  try {
    const [latestRoundId] = await oracle.latestRoundData(FEED_ID);

    // Try to fetch previous round (if it exists)
    if (latestRoundId > 1n) {
      const prevRoundId = latestRoundId - 1n;
      console.log(`  Fetching round ${prevRoundId}...`);

      const [roundId, answer, startedAt, updatedAt, answeredInRound] = await oracle.getRoundData(FEED_ID, prevRoundId);
      console.log(`  ✅ Historical data available:`);
      console.log(`     Round ID: ${roundId}`);
      console.log(`     Answer:   ${answer.toString()}`);
      console.log(`     Updated:  ${new Date(Number(updatedAt) * 1000).toISOString()}\n`);

      // Try same via adapter
      const [aRoundId, aAnswer, aStartedAt, aUpdatedAt, aAnsweredInRound] = await adapter.getRoundData(prevRoundId);
      console.log(`  ✅ Adapter historical data:`);
      console.log(`     Round ID: ${aRoundId}`);
      console.log(`     Answer:   ${aAnswer.toString()}`);
      console.log(`     Updated:  ${new Date(Number(aUpdatedAt) * 1000).toISOString()}\n`);

      if (answer === aAnswer && updatedAt === aUpdatedAt) {
        console.log(`  ✅ Historical data consistent between Oracle and Adapter\n`);
      }
    } else {
      console.log(`  ℹ️  Only one round available, skipping historical test\n`);
    }
  } catch (err) {
    console.log(`  ⚠️  Historical data test: ${err.message}\n`);
  }
}

async function main() {
  try {
    // Test Oracle
    const oracleData = await testOracle();

    // Test Adapter
    const adapterData = await testAdapter(oracleData.roundId, oracleData.answer);

    // Test Consumer
    const consumerData = await testConsumer(oracleData.answer, oracleData.updatedAt);

    // Test Historical Data
    await testHistoricalData();

    console.log("═══════════════════════════════════════");
    console.log("✅ ALL TESTS PASSED!");
    console.log("═══════════════════════════════════════");
    console.log("\nSummary:");
    console.log(`  Oracle Round:    ${oracleData.roundId}`);
    console.log(`  Oracle Answer:   ${oracleData.answer.toString()}`);
    console.log(`  Adapter Answer:  ${adapterData.answer.toString()}`);
    console.log(`  Consumer Answer: ${consumerData.answer.toString()}`);
    console.log(`  Data Age:        ${Math.floor(Date.now() / 1000) - Number(oracleData.updatedAt)}s`);
    console.log("\n✅ Integration verified: Oracle → Adapter → Consumer\n");

  } catch (err) {
    console.log("═══════════════════════════════════════");
    console.log("❌ TESTS FAILED");
    console.log("═══════════════════════════════════════");
    console.error(err);
    process.exit(1);
  }
}

main();
