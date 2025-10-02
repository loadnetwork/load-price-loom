# Pre-Mainnet Deployment Checklist

Technical checklist for production readiness. Use 2-3 months before mainnet launch.

---

## 🏗️ Smart Contract Architecture

### Upgradeability Strategy

- [ ] **Decide on upgrade approach:**
  - [ ] Option A: Phase-aware adapters (recommended) - See [phase-support-roadmap.md](./phase-support-roadmap.md)
  - [ ] Option B: Oracle proxy pattern (UUPS/Transparent)
  - [ ] Option C: Accept full redeployment + consumer migration (not recommended for DeFi)

- [ ] **If using phase-aware adapters:**
  - [ ] Implement `PriceLoomPhaseAwareAdapter.sol`
  - [ ] Add phase management functions (`addPhase`, `currentPhaseId`)
  - [ ] Implement round ID encoding/decoding logic
  - [ ] Add access control for phase admin
  - [ ] Update factory to support phase-aware deployment
  - [ ] Write comprehensive phase transition tests
  - [ ] Document phase upgrade procedures

- [ ] **If using oracle proxy:**
  - [ ] Refactor `PriceLoomOracle` for proxy compatibility
  - [ ] Add storage gaps for future upgrades
  - [ ] Implement initializer pattern
  - [ ] Add UUPS/Transparent proxy deployment scripts
  - [ ] Set up multisig for upgrade governance
  - [ ] Write upgrade simulation tests

### Consumer Safety

- [ ] **Improve TestPriceConsumer** to demonstrate best practices:
  - [ ] Add stale data checks (`answeredInRound >= roundId`)
  - [ ] Add timestamp freshness validation
  - [ ] Add price sanity checks (`answer > 0`)
  - [ ] Add circuit breaker / fallback mechanism
  - [ ] Document why each check is necessary

- [ ] **Create additional example consumers:**
  - [ ] `SafePriceConsumer.sol` with all safety checks
  - [ ] `TwapConsumer.sol` for time-weighted average prices
  - [ ] `MultiOracleConsumer.sol` for price aggregation across sources

### Oracle Hardening

- [ ] **Per-feed pause capability** (currently global pause only)
  - [ ] Add `_feedPaused[feedId]` mapping
  - [ ] Add `pauseFeed(feedId)` and `unpauseFeed(feedId)` functions
  - [ ] Add `whenFeedNotPaused(feedId)` modifier

- [ ] **Price deviation limits** (optional, already have some)
  - [ ] Add max price change percentage guard
  - [ ] Add min/max price bounds enforcement (already exists)
  - [ ] Log suspicious price movements

- [ ] **Emergency procedures:**
  - [ ] Document emergency shutdown process
  - [ ] Create emergency response runbook
  - [ ] Test pause/unpause procedures

---

## 🔐 Security

### Audits

- [ ] **Internal security review:**
  - [ ] Manual code review by multiple engineers
  - [ ] Review all `onlyRole` and access control
  - [ ] Review all external calls
  - [ ] Review arithmetic (overflow/underflow)
  - [ ] Review reentrancy guards

- [ ] **External audit:**
  - [ ] Select reputable audit firm
  - [ ] Scope: Core oracle + adapter + phase support (if implemented)
  - [ ] Timeline: 4-6 weeks (2 weeks audit + 2 weeks fixes + 2 weeks reaudit)
  - [ ] Publish audit report publicly

- [ ] **Formal verification** (optional):
  - [ ] Certora for critical invariants
  - [ ] Focus on round finalization logic, median calculation, bitmap deduplication

### Access Control

- [ ] **Set up governance:**
  - [ ] Deploy multisig for admin roles (Gnosis Safe recommended)
  - [ ] Minimum 3-of-5 or 4-of-7 threshold
  - [ ] Document signer identities and backup procedures
  - [ ] Test multisig execution on testnet

- [ ] **Role assignments:**
  - [ ] `DEFAULT_ADMIN_ROLE` → Multisig (governs all roles)
  - [ ] `FEED_ADMIN_ROLE` → Multisig or operations EOA (for feed config updates)
  - [ ] `PAUSER_ROLE` → Bot + Multisig (for emergency pause)
  - [ ] `PHASE_ADMIN_ROLE` → Multisig only (if using phase adapters)

- [ ] **Timelock** (recommended for mainnet):
  - [ ] Deploy OpenZeppelin TimelockController
  - [ ] Set minimum delay (e.g., 48 hours for governance actions)
  - [ ] Route admin actions through timelock
  - [ ] Announce changes on-chain before execution

---

## 🧪 Testing

### Test Coverage

- [ ] **Unit tests:** >95% coverage
  - [ ] Oracle: submission, finalization, timeout, stale rollover
  - [ ] Adapter: data passthrough, phase transitions (if applicable)
  - [ ] Consumer: safety checks, error handling
  - [ ] Factory: deterministic deployment, predictable addresses

- [ ] **Integration tests:**
  - [ ] End-to-end: deploy oracle → bootstrap feeds → run bot → consume prices
  - [ ] Multi-feed scenarios: 5+ feeds running concurrently
  - [ ] Timeout scenarios: operator failures, stale data
  - [ ] Upgrade scenarios: oracle version change, phase transitions

- [ ] **Fuzz tests:**
  - [ ] Foundry invariant testing: median calculation always correct
  - [ ] Random operator submissions: no invalid state transitions
  - [ ] Random timestamps: heartbeat/deviation logic correct

### Testnet Deployment

- [ ] **Deploy to public testnet** (Sepolia or Holesky):
  - [ ] Run for minimum 2 weeks
  - [ ] Simulate mainnet operator setup (6+ operators, 30s heartbeat)
  - [ ] Test bot resilience: kill and restart multiple times
  - [ ] Test upgrade procedures: add new phase, migrate feed
  - [ ] Invite community to integrate and test

- [ ] **Stress testing:**
  - [ ] 100+ feeds simultaneously
  - [ ] 1000+ rounds per feed
  - [ ] Operator failures: 50% offline, then recovery
  - [ ] Network congestion: high gas prices, slow blocks

---

## 📚 Documentation

### Technical Docs

- [ ] **Architecture overview:**
  - [ ] System diagram (oracle → adapter → consumer flow)
  - [ ] Round lifecycle flowchart
  - [ ] Operator workflow diagram

- [ ] **Integration guide:**
  - [ ] How to deploy a new feed
  - [ ] How to consume prices in Solidity
  - [ ] How to run an operator bot
  - [ ] How to upgrade oracle/adapter

- [ ] **API reference:**
  - [ ] All public functions documented with NatSpec
  - [ ] Event documentation
  - [ ] Error code reference

- [ ] **Security best practices:**
  - [ ] Consumer safety checklist (stale checks, circuit breakers)
  - [ ] Operator key management
  - [ ] Multisig procedures

### Operational Docs

- [ ] **Runbooks:**
  - [ ] Emergency pause procedure
  - [ ] Oracle upgrade procedure (step-by-step)
  - [ ] Operator onboarding/offboarding
  - [ ] Feed configuration changes

- [ ] **Monitoring setup:**
  - [ ] List of metrics to track (price age, submission count, operator health)
  - [ ] Alert thresholds (e.g., alert if no submissions for >5min)
  - [ ] Dashboard examples (Grafana, Dune Analytics)

---

## 🤖 Infrastructure

### Operator Bots

- [ ] **Production bot setup:**
  - [ ] Convert from `.mjs` to TypeScript (optional, for robustness)
  - [ ] Add structured logging (Winston, Pino)
  - [ ] Add metrics export (Prometheus)
  - [ ] Add health check endpoint (for load balancer)
  - [ ] Add graceful shutdown handling

- [ ] **Operator key management:**
  - [ ] Hardware wallets (Ledger) or KMS (AWS KMS, GCP KMS)
  - [ ] Never store private keys in code or env vars (use secrets manager)
  - [ ] Separate hot wallets (for bot) and cold wallets (for backup)

- [ ] **Redundancy:**
  - [ ] Minimum 3 operators per feed
  - [ ] Operators in different geographic regions
  - [ ] Operators using different RPC providers
  - [ ] Automatic failover if primary operator goes down

### Deployment Scripts

- [ ] **Forge scripts for mainnet:**
  - [ ] `DeployOracleMainnet.s.sol` with verification
  - [ ] `DeployAdapterFactory.s.sol`
  - [ ] `BootstrapFeeds.s.sol` (reads from `feeds-mainnet.json`)
  - [ ] `UpgradeOracle.s.sol` (if using proxy) or `AddPhase.s.sol` (if using phases)

- [ ] **Deployment procedure:**
  - [ ] Use --verify flag for automatic Etherscan verification
  - [ ] Save deployment addresses to secure location
  - [ ] Test deployed contracts on-chain before announcing
  - [ ] Renounce deployer roles after setup

---

## 📊 Monitoring & Alerting

### Metrics to Track

- [ ] **Oracle health:**
  - [ ] Number of active feeds
  - [ ] Submissions per round (should be ≥ minSubmissions)
  - [ ] Round finalization time (should be < heartbeat)
  - [ ] Price staleness (time since last update)

- [ ] **Operator health:**
  - [ ] Successful submissions per operator
  - [ ] Failed submissions (by error type: NotDue, WrongRound, etc.)
  - [ ] Operator balance (for gas refills)
  - [ ] Bot uptime

- [ ] **Consumer activity:**
  - [ ] Number of unique consumers calling adapter
  - [ ] Read frequency per feed
  - [ ] Failed reads (NoData errors)

### Alerts

- [ ] **Critical alerts** (immediate action required):
  - [ ] Oracle paused unexpectedly
  - [ ] No submissions for >5 minutes
  - [ ] Price hasn't updated for >2× heartbeat
  - [ ] All operators failing

- [ ] **Warning alerts** (investigate within 1 hour):
  - [ ] Operator balance <0.1 ETH
  - [ ] >50% of submissions failing
  - [ ] Price deviated >20% from external sources
  - [ ] Round took >2× heartbeat to finalize

---

## 💰 Economic Security

### Operator Incentives

- [ ] **Decide on operator compensation model:**
  - [ ] Option A: No payment (volunteer operators for testnet/small feeds)
  - [ ] Option B: Gas reimbursement only
  - [ ] Option C: Gas + fixed reward per submission
  - [ ] Option D: Gas + percentage of protocol revenue

- [ ] **Operator selection criteria:**
  - [ ] Technical requirements (server specs, uptime SLA)
  - [ ] Geographic diversity (no more than 33% in one region)
  - [ ] Reputation (known entities, staking/bonding)

### Fee Model (Optional)

- [ ] **Consumer fees for price reads:**
  - [ ] Implement `feeRecipient` and `feeAmount` in adapter
  - [ ] Use fees to pay operators or accumulate in treasury
  - [ ] Whitelist certain consumers (e.g., protocol-owned contracts)

---

## 🚀 Launch Procedure

### Pre-Launch (T-2 weeks)

- [ ] Finalize mainnet feed configurations (`feeds-mainnet.json`)
- [ ] Recruit and onboard mainnet operators
- [ ] Deploy to mainnet in "paused" state
- [ ] Verify all contracts on Etherscan
- [ ] Run smoke tests on deployed contracts

### Launch Day (T-0)

- [ ] Unpause oracle
- [ ] Start operator bots
- [ ] Verify first round finalizes correctly
- [ ] Announce launch (Twitter, Discord, docs site)
- [ ] Monitor closely for first 24 hours

### Post-Launch (T+1 week)

- [ ] Publish post-mortem if any issues
- [ ] Onboard first external consumers
- [ ] Set up ongoing monitoring dashboards
- [ ] Schedule first oracle upgrade dry-run (even if no upgrade needed)

---

## 📝 Phase Support Implementation

See [phase-support-roadmap.md](./phase-support-roadmap.md) for detailed specification.

**Critical for mainnet if:**
- Third-party consumers will integrate
- Historical round data must remain accessible
- Oracle upgrades are anticipated

**Implementation checklist:**
- [ ] Create `PriceLoomPhaseAwareAdapter.sol`
- [ ] Implement round ID encoding: `(phaseId << 64) | aggregatorRoundId`
- [ ] Add `addPhase()` admin function
- [ ] Add phase lookup in `getRoundData()`
- [ ] Write phase transition tests
- [ ] Update factory to deploy phase-aware adapters
- [ ] Document upgrade procedures



**Deferred Items (Acceptable for v1):**
- Phase support (document limitation, implement before mainnet)
- Per-feed pause (global pause is sufficient for v1)
- Fee model (can add post-launch)
- Formal verification (high cost, optional)

**Must Complete Before Mainnet:**
- ✅ External security audit
- ✅ 2+ weeks of testnet operation
- ✅ Phase-aware adapters OR documented migration plan
- ✅ Multisig governance setup
- ✅ Monitoring and alerting infrastructure
- ✅ Emergency response procedures documented
