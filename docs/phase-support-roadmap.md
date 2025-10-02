# Phase Support Roadmap for Production Upgrades

## Executive Summary

**Current State:** Price Loom uses single-phase adapters with immutable oracle references. This works for initial deployment but creates **round ID continuity issues** when upgrading the oracle backend.

**Production Goal:** Implement Chainlink-style phase-aware adapters that maintain stable addresses and historical round ID interpretation across oracle upgrades.

---

## The Problem: Why Phases Matter

### Current Architecture (v0 - No Phases)

```
┌─────────────────────────────────────────┐
│ PriceLoomAggregatorV3Adapter            │
│ ├─ oracle: immutable (0x5FbD...)        │  ← Fixed at deployment
│ ├─ feedId: immutable (0x3f32...)        │  ← Fixed at deployment
│ └─ getRoundData(uint80 roundId)         │
│    └─ oracle.getRoundData(feedId, roundId) │ ← Direct passthrough
└─────────────────────────────────────────┘
```

**Round ID Format:** Raw `uint80` from oracle (0, 1, 2, 3, ...)

### The Upgrade Problem

**Scenario:** 6 months after launch, you discover a critical bug in `PriceLoomOracle` and need to deploy `PriceLoomOracleV2`.

**Option 1 - Deploy New Adapter (Current Approach):**
```
Old Adapter (0xD916...A0A2) → Old Oracle (0x5FbD...0aa3) ✅ Rounds 1-1000
New Adapter (0xABCD...1234) → New Oracle (0x7890...CDEF) ✅ Rounds 1-500

Consumer Contract reads from 0xD916...A0A2
❌ Still using old oracle! Must upgrade every consumer manually.
```

**Problem:** Consumer contracts have hardcoded adapter addresses. Migrating requires:
1. Deploy new oracle
2. Deploy new adapter
3. Update **every consumer contract** (risky, slow, expensive)
4. Historical round IDs (1-1000) now exist in OLD adapter, new rounds (1-500) in NEW adapter
5. Round ID "1" is ambiguous - which oracle?

**Option 2 - Use Proxy for Oracle (Complex):**
```
Adapter (0xD916...A0A2) → Oracle Proxy (0x5FbD...0aa3)
                              ↓
                         Implementation can change
```

**Problem:** Requires full UUPS/Transparent proxy refactor:
- Storage layout management (gaps, ordering)
- Initializer patterns (no constructors)
- Upgrade governance & timelock
- Security audits for proxy interactions
- Added gas costs

---

## The Solution: Phase-Aware Adapters (Chainlink Pattern)

### How Chainlink Does It

Chainlink's `AggregatorProxy` encodes **phases** into round IDs:

```solidity
// Round ID encoding
uint80 roundId = (uint80(phaseId) << 64) | uint64(aggregatorRoundId);

// Example:
// Phase 1, Round 42  → 0x0000000000000001000000000000002A (18446744073709551658)
// Phase 2, Round 1   → 0x0000000000000002000000000000001  (36893488147419103233)
```

**Benefits:**
1. **Stable adapter address** - Never changes
2. **Historical continuity** - Old round IDs remain valid
3. **Unambiguous rounds** - Phase ID disambiguates which oracle
4. **Chainlink-compatible** - Exact same pattern

### Proposed Architecture (v1 - With Phases)

```
┌─────────────────────────────────────────────────────────┐
│ PriceLoomPhaseAwareAdapter (NEW)                        │
│ ├─ currentPhaseId: uint16                               │  ← Admin can increment
│ ├─ phases[phaseId] → {oracle, feedId}                   │  ← Track all phases
│ │                                                        │
│ ├─ latestRoundData()                                    │
│ │   1. Get data from phases[currentPhaseId].oracle     │
│ │   2. Encode: roundId = (phaseId << 64) | oracleRound │
│ │   3. Return encoded roundId + data                    │
│ │                                                        │
│ └─ getRoundData(uint80 encodedRoundId)                  │
│     1. Decode: phaseId = roundId >> 64                  │
│     2. Decode: oracleRound = uint64(roundId)            │
│     3. Lookup: phases[phaseId]                          │
│     4. Call that phase's oracle with oracleRound        │
│     5. Re-encode and return                             │
└─────────────────────────────────────────────────────────┘
```

**Upgrade Flow:**

```
Time T0 (Launch):
  Adapter.addPhase(OracleV1, feedId)  // phaseId = 1
  Rounds: 1, 2, 3, ... 1000
  Encoded: 0x0000...0001...0001, 0x0000...0001...0002, ...

Time T1 (6 months later - Bug discovered):
  Deploy OracleV2
  Adapter.addPhase(OracleV2, feedId)  // phaseId = 2 (admin call)

Time T1+:
  New rounds: 1, 2, 3, ... 500
  Encoded: 0x0000...0002...0001, 0x0000...0002...0002, ...

Consumer Contract:
  ✅ adapter.latestRoundData() → Returns phase 2 data automatically
  ✅ adapter.getRoundData(phase1Round42) → Still works! Reads from old oracle
  ✅ No code changes needed in consumer!
```

---

## Implementation Specification

### 1. Data Structures

```solidity
// In PriceLoomPhaseAwareAdapter.sol

struct Phase {
    IOracleReader oracle;
    bytes32 feedId;
    uint80 startingRoundId;  // First round in this phase (for validation)
}

mapping(uint16 => Phase) public phases;
uint16 public currentPhaseId;

// Events
event PhaseAdded(uint16 indexed phaseId, address indexed oracle, bytes32 indexed feedId);
event PhaseChanged(uint16 indexed previousPhaseId, uint16 indexed newPhaseId);
```

### 2. Core Functions

```solidity
/// @notice Add a new phase (admin only)
function addPhase(IOracleReader newOracle, bytes32 newFeedId) external onlyAdmin {
    require(address(newOracle) != address(0), "Zero oracle");

    // Verify feed exists in new oracle
    OracleTypes.FeedConfig memory cfg = newOracle.getConfig(newFeedId);
    require(cfg.decimals != 0, "Feed not found");

    // Enforce decimals consistency across phases
    if (currentPhaseId > 0) {
        OracleTypes.FeedConfig memory prevCfg = phases[currentPhaseId].oracle.getConfig(
            phases[currentPhaseId].feedId
        );
        require(cfg.decimals == prevCfg.decimals, "Decimals must match");
    }

    currentPhaseId++;
    phases[currentPhaseId] = Phase({
        oracle: newOracle,
        feedId: newFeedId,
        startingRoundId: 1  // New phase always starts at round 1
    });

    emit PhaseAdded(currentPhaseId, address(newOracle), newFeedId);
}

/// @notice Get latest round data (encodes current phase)
function latestRoundData()
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
{
    Phase memory phase = phases[currentPhaseId];
    require(address(phase.oracle) != address(0), "No phase");

    (uint80 oracleRoundId, int256 a, uint256 s, uint256 u, uint80 oracleAnsweredIn) =
        phase.oracle.latestRoundData(phase.feedId);

    // Encode phase into round IDs
    roundId = _encodeRoundId(currentPhaseId, oracleRoundId);
    answeredInRound = _encodeRoundId(currentPhaseId, oracleAnsweredIn);

    return (roundId, a, s, u, answeredInRound);
}

/// @notice Get historical round data (decodes phase from roundId)
function getRoundData(uint80 encodedRoundId)
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
{
    (uint16 phaseId, uint64 oracleRoundId) = _decodeRoundId(encodedRoundId);

    Phase memory phase = phases[phaseId];
    require(address(phase.oracle) != address(0), "Phase not found");

    (uint80 oRid, int256 a, uint256 s, uint256 u, uint80 oAir) =
        phase.oracle.getRoundData(phase.feedId, uint80(oracleRoundId));

    // Re-encode with correct phase
    roundId = _encodeRoundId(phaseId, oRid);
    answeredInRound = _encodeRoundId(phaseId, oAir);

    return (roundId, a, s, u, answeredInRound);
}

/// @dev Encode phaseId and oracleRoundId into a single uint80
function _encodeRoundId(uint16 phaseId, uint80 oracleRoundId) internal pure returns (uint80) {
    // phaseId in upper 16 bits, oracleRoundId in lower 64 bits
    return (uint80(phaseId) << 64) | uint64(oracleRoundId);
}

/// @dev Decode uint80 into phaseId and oracleRoundId
function _decodeRoundId(uint80 encodedRoundId) internal pure returns (uint16 phaseId, uint64 oracleRoundId) {
    phaseId = uint16(encodedRoundId >> 64);
    oracleRoundId = uint64(encodedRoundId);
}
```

### 3. Access Control

```solidity
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

bytes32 public constant PHASE_ADMIN_ROLE = keccak256("PHASE_ADMIN_ROLE");

modifier onlyPhaseAdmin() {
    require(hasRole(PHASE_ADMIN_ROLE, msg.sender), "Not phase admin");
    _;
}
```

### 4. Factory Support

```solidity
// In PriceLoomAdapterFactory.sol (future)

function deployPhaseAwareAdapter(bytes32 feedId, address initialAdmin)
    external
    returns (address adapter)
{
    PriceLoomPhaseAwareAdapter newAdapter = new PriceLoomPhaseAwareAdapter(initialAdmin);

    // Add initial phase (current oracle)
    newAdapter.addPhase(oracle, feedId);

    // Grant admin role and renounce deployer role
    newAdapter.grantRole(PHASE_ADMIN_ROLE, initialAdmin);
    newAdapter.renounceRole(DEFAULT_ADMIN_ROLE, address(this));

    return address(newAdapter);
}
```

---

## Testing Requirements

### Unit Tests

```solidity
// test/adapter/PhaseAwareAdapter.t.sol

contract PhaseAwareAdapterTest is Test {
    function testSinglePhase() { /* Basic functionality */ }

    function testPhaseTransition() {
        // 1. Create phase 1, submit 100 rounds
        // 2. Add phase 2, submit 50 rounds
        // 3. Verify latestRoundData returns phase 2
        // 4. Verify getRoundData(phase1Round50) still works
        // 5. Verify round IDs are correctly encoded
    }

    function testRoundIdEncodingDecoding() {
        // Test encode/decode roundtrip for all phases
    }

    function testHistoricalContinuity() {
        // Verify old round IDs remain valid after phase upgrade
    }

    function testDecimalsConsistency() {
        // Should revert if new phase has different decimals
    }

    function testPhaseAdminPermissions() {
        // Only PHASE_ADMIN_ROLE can add phases
    }

    function testInvalidPhaseId() {
        // getRoundData with non-existent phase should revert
    }
}
```

### Integration Tests

```solidity
// test/integration/PhaseUpgrade.t.sol

contract PhaseUpgradeIntegrationTest is Test {
    function testFullUpgradePath() {
        // 1. Deploy OracleV1 + PhaseAdapter
        // 2. Run bot, accumulate 1000 rounds
        // 3. Deploy consumer, verify reads
        // 4. Deploy OracleV2 (with bug fix)
        // 5. Add phase 2 to adapter
        // 6. Verify consumer still works without changes
        // 7. Verify historical rounds from phase 1 accessible
        // 8. Run bot on V2, accumulate new rounds
        // 9. Verify monotonic round ID progression
    }
}
```

---

## Migration Path for Existing Deployments

### For Current v0 Deployments (No Phases)

**Scenario:** You have existing `PriceLoomAggregatorV3Adapter` instances deployed without phase support.

**Migration Strategy:**

```
Step 1: Deploy Phase-Aware Factory
  - Deploy new PriceLoomPhaseAwareAdapterFactory
  - Keep old non-phase adapters running

Step 2: Gradual Consumer Migration
  For each feed:
    1. Deploy new phase-aware adapter at new address
    2. Initialize with current oracle as Phase 1
    3. Update consumer contracts one-by-one to point to new adapter
    4. Old adapter remains live for unmigrated consumers

Step 3: After Full Migration
  - All consumers now use phase-aware adapters
  - Old adapters can be deprecated
  - Future oracle upgrades are seamless
```

**Note:** This is a one-time migration. Once consumers use phase-aware adapters, future upgrades require no consumer changes.

---

## When to Implement Phases

### Don't Implement If:
- ❌ Prototype/testnet only
- ❌ Planning full protocol redeployment anyway
- ❌ No plans to ever upgrade oracle
- ❌ Consumers are all upgradeable proxies (can update adapter address)

### Do Implement If:
- ✅ **Mainnet deployment** with long-term support
- ✅ **DeFi integrations** expecting stable adapter addresses
- ✅ **Historical data is critical** (e.g., liquidation systems)
- ✅ **Third-party consumers** you can't force to upgrade
- ✅ **Chainlink compatibility** is a core value prop
- ✅ **Enterprise/institutional** users requiring stability guarantees

---

## Decision Matrix for Current Stage

| Factor | Current Priority | Notes |
|--------|------------------|-------|
| **Mainnet Readiness** | Medium | If launching soon, add phases now |
| **Consumer Adoption** | Low initially | Can add later if just testing |
| **Upgrade Likelihood** | Medium | Bugs are common in v1 oracles |
| **Implementation Cost** | Low | ~200 LOC, 2-3 days work |
| **Testing Cost** | Medium | Thorough phase transition testing needed |
| **Documentation Cost** | Low | This doc + inline comments |

**Recommendation for Current Stage:**

Since you're in **testnet/development mode** and explicitly **not prioritizing upgradeability for simplicity**, you can **defer phase support** with these safeguards:

1. ✅ **Document the limitation clearly** (this file)
2. ✅ **Add TODO markers** in adapter code
3. ✅ **Include in pre-mainnet checklist**
4. ✅ **Test phase-aware adapter in parallel** (optional)
5. ✅ **Use deterministic adapters** so re-deployment is predictable

---

## Action Items & TODOs

### Immediate (Current Stage)

- [x] Create this documentation (phase-support-roadmap.md)
- [ ] Add TODO comments in `PriceLoomAggregatorV3Adapter.sol`
- [ ] Add warning in `adapter-guide.md` about round ID continuity
- [ ] Add item to pre-mainnet deployment checklist

### Before Mainnet

- [ ] Implement `PriceLoomPhaseAwareAdapter.sol`
- [ ] Add comprehensive tests for phase transitions
- [ ] Update factory to support both adapter types
- [ ] Document migration path for existing deployments
- [ ] Get phase-aware adapter audited separately

### Post-Mainnet (When Upgrade Needed)

- [ ] Deploy new oracle version
- [ ] Call `addPhase()` on existing adapters
- [ ] Verify historical round continuity
- [ ] Update documentation with actual upgrade experience

---

## Code TODOs to Add

### In `src/adapter/PriceLoomAggregatorV3Adapter.sol`

```solidity
// TODO: [PRODUCTION] This adapter uses single-phase round IDs.
// For mainnet, implement PriceLoomPhaseAwareAdapter to support:
//   1. Oracle upgrades without changing adapter address
//   2. Historical round ID continuity across phases
//   3. Phase encoding: roundId = (phaseId << 64) | aggregatorRoundId
// See: docs/phase-support-roadmap.md
// Tracked in: [ISSUE-XXX]

contract PriceLoomAggregatorV3Adapter is AggregatorV3Interface {
    // ...
}
```

### In `docs/adapter-guide.md`

```markdown
## ⚠️ Production Considerations

### Round ID Continuity

The current adapter implementation uses **single-phase round IDs**. This means:

- ✅ Works perfectly for single oracle deployments
- ❌ **Historical round IDs break if oracle address changes**
- ❌ **Consumers must be updated manually when upgrading oracle**

For production mainnet deployments, use **phase-aware adapters** instead:
- Stable adapter address across oracle upgrades
- Historical continuity (old round IDs remain valid)
- Chainlink-compatible phase encoding

See [phase-support-roadmap.md](./phase-support-roadmap.md) for full details.
```

### In `.github/pre-mainnet-checklist.md` (create if doesn't exist)

```markdown
# Pre-Mainnet Deployment Checklist

## Smart Contract Readiness

- [ ] **Phase-aware adapters implemented** (see phase-support-roadmap.md)
  - [ ] PriceLoomPhaseAwareAdapter.sol written
  - [ ] Phase transition tests passing
  - [ ] Factory supports phase-aware deployment
  - [ ] Migration path documented

- [ ] **Oracle upgradeability strategy decided**
  - [ ] Phase-aware adapters (recommended), OR
  - [ ] Proxy pattern for oracle, OR
  - [ ] Accept full redeployment + consumer updates

## Documentation

- [ ] Document which adapter type is deployed
- [ ] Document upgrade procedures
- [ ] Add emergency response playbook

## Security

- [ ] Phase-aware adapter audited (if using)
- [ ] Upgrade governance reviewed
```

---

## Alternative: Proxy Pattern Comparison

For completeness, here's why phase-aware adapters are preferred over oracle proxies:

| Aspect | Phase-Aware Adapter | Oracle Proxy |
|--------|---------------------|--------------|
| **Complexity** | Medium (adapter logic) | High (storage, init, gaps) |
| **Gas Cost** | No overhead | +2100 gas per delegatecall |
| **Security Surface** | Admin on adapter only | Admin + proxy + implementation |
| **Testing** | Standard unit tests | Need upgrade simulation tests |
| **Audit Cost** | Lower (smaller surface) | Higher (proxy patterns complex) |
| **Flexibility** | Can change oracle AND feedId | Oracle only, feedId fixed |
| **Chainlink Compat** | Exact match | Exact match |
| **Implementation Time** | 2-3 days | 1-2 weeks |

**Verdict:** Phase-aware adapters are simpler, cheaper, and more flexible. Only use oracle proxies if you need to upgrade multiple feeds atomically.

---

## References

- [Chainlink AggregatorProxy.sol](https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol)
- [Chainlink Phase Aggregator](https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.7/dev/AggregatorProxy.sol)
- [OpenZeppelin UUPS Upgrades](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable)
- Price Loom Adapter Guide: `docs/adapter-guide.md`
- Current implementation: `src/adapter/PriceLoomAggregatorV3Adapter.sol`

---

## Conclusion

**For Current Stage (Development/Testing):**
- ✅ Current single-phase adapter is appropriate
- ✅ Document limitation clearly
- ✅ Add TODO markers for future
- ✅ Defer implementation until mainnet prep

**For Production (Mainnet):**
- ⚠️ **Must implement phase-aware adapters** before launch if:
  - Third-party consumers will integrate
  - Historical round data is critical
  - Oracle upgrades are anticipated
- 🎯 Target: Implement 2-3 months before mainnet launch
- 📋 Track in issue tracker with "pre-mainnet" label

**Summary:** You've correctly identified that upgradeability adds complexity. Deferring phase support for simplicity is reasonable **for current testing stage**, but document the limitation clearly and plan to implement before production mainnet deployment.
