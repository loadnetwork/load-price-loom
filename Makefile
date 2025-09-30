# Default environment
ALPHA_RPC_URL ?= https://alphanet.load.network

# Default network: alphanet
RPC_URL ?= $(ALPHA_RPC_URL)
CHAIN_ID ?= 9496

# Helpers: quickly re-run any target under a specific network
.PHONY: anvil-% alphanet-% doctor
anvil-%:
	@$(MAKE) $* RPC_URL=http://127.0.0.1:8545 CHAIN_ID=31337
alphanet-%:
	@$(MAKE) $* RPC_URL=$(ALPHA_RPC_URL) CHAIN_ID=9496

# Preflight: ensure the RPC_URL chain id matches CHAIN_ID
define REQUIRE_CHAIN
@cid=$$(cast chain-id --rpc-url "$(RPC_URL)" 2>/dev/null || true); \
 if [ -z "$$cid" ]; then \
   echo "Unable to reach RPC_URL: $(RPC_URL)" && exit 1; \
 fi; \
 if [ "$$cid" != "$(CHAIN_ID)" ]; then \
   echo "Chain ID mismatch: expected $(CHAIN_ID), got $$cid (RPC: $(RPC_URL))" && exit 1; \
 fi
endef

doctor:
	@echo "RPC_URL = $(RPC_URL)"
	@echo "CHAIN_ID = $(CHAIN_ID)"
	@echo -n "Remote chain-id: "; cast chain-id --rpc-url "$(RPC_URL)" || true

.PHONY: help build test fmt snapshot clean \
	deploy-factory create-feeds-json deploy-adapters-json poke-feeds-json \
	create-feed-env bootstrap-all e2e-demo e2e-clean

help:
	@echo "Targets:"
	@echo "  build                 - forge build"
	@echo "  test                  - forge test"
	@echo "  fmt                   - forge fmt"
	@echo "  snapshot              - forge snapshot"
	@echo "  clean                 - forge clean"
	@echo "  deploy-factory        - Deploy Adapter Factory (requires ORACLE)"
	@echo "  create-feeds-json     - Create feeds from FEEDS_FILE (requires ORACLE)"
	@echo "  deploy-adapters-json  - Deploy adapters from FEEDS_FILE (requires FACTORY)"
	@echo "  poke-feeds-json       - Poke feeds from FEEDS_FILE (requires ORACLE)"
	@echo "  create-feed-env       - Create a single feed from env vars (requires ORACLE, FEED_DESC, etc.)"
	@echo "  bootstrap-all         - Deploy oracle+factory, then create feeds and adapters from FEEDS_FILE (requires ADMIN)"

build:
	forge build

test:
	forge test

fmt:
	forge fmt

snapshot:
	forge snapshot

clean:
	forge clean

# Scripts (use RPC_URL, broadcast; pick up other params from environment)

deploy-factory:
	$(REQUIRE_CHAIN)
	@if [ -z "$$ORACLE" ]; then echo "ORACLE env var required" && exit 1; fi
	forge script script/DeployFactory.s.sol:DeployFactory --rpc-url "$(RPC_URL)" --chain-id $(CHAIN_ID) --broadcast -vvvv

create-feeds-json:
	$(REQUIRE_CHAIN)
	@if [ -z "$$ORACLE" ]; then echo "ORACLE env var required" && exit 1; fi
	forge script script/CreateFeedsFromJson.s.sol:CreateFeedsFromJson --rpc-url "$(RPC_URL)" --chain-id $(CHAIN_ID) --broadcast -vvvv

deploy-adapters-json:
	$(REQUIRE_CHAIN)
	@if [ -z "$$FACTORY" ]; then echo "FACTORY env var required" && exit 1; fi
	forge script script/DeployDeterministicAdaptersFromJson.s.sol:DeployDeterministicAdaptersFromJson --rpc-url "$(RPC_URL)" --chain-id $(CHAIN_ID) --broadcast -vvvv

poke-feeds-json:
	$(REQUIRE_CHAIN)
	@if [ -z "$$ORACLE" ]; then echo "ORACLE env var required" && exit 1; fi
	forge script script/PokeFeedsFromJson.s.sol:PokeFeedsFromJson --rpc-url "$(RPC_URL)" --chain-id $(CHAIN_ID) --broadcast -vvvv

create-feed-env:
	$(REQUIRE_CHAIN)
	@if [ -z "$$ORACLE" ]; then echo "ORACLE env var required" && exit 1; fi
	@if [ -z "$$FEED_DESC" ]; then echo "FEED_DESC env var required" && exit 1; fi
	forge script script/CreateSingleFeedEnv.s.sol:CreateSingleFeedEnv --rpc-url "$(RPC_URL)" --chain-id $(CHAIN_ID) --broadcast -vvvv

bootstrap-all:
	$(REQUIRE_CHAIN)
	@if [ -z "$$ADMIN" ]; then echo "ADMIN env var required" && exit 1; fi
	forge script script/BootstrapOracleAndAdapters.s.sol:BootstrapOracleAndAdapters --rpc-url "$(RPC_URL)" --chain-id $(CHAIN_ID) --broadcast -vvvv

# End-to-end local demo using Anvil accounts and feeds-anvil.json
# Requires: anvil running at RPC_URL; Node.js available
E2E_FEED_DESC ?= ar/bytes-testv1
E2E_INTERVAL_MS ?= 30000

e2e-demo:
	@echo "[1/4] Bootstrapping oracle+factory+feeds+adapters from feeds-anvil.json"
	ADMIN=$${ADMIN:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266} \
	FEEDS_FILE=feeds-anvil.json \
	$(MAKE) bootstrap-all RPC_URL=$(RPC_URL) CHAIN_ID=$(CHAIN_ID)
	@echo "[2/4] Extracting addresses from out/e2e-addresses.txt"
	@( test -f out/e2e-addresses.txt ) || (echo "Missing out/e2e-addresses.txt; bootstrap failed?" && exit 1)
	$(eval ORACLE := $(shell awk -F= '/^oracle=/{print $$2}' out/e2e-addresses.txt))
	$(eval ADAPTER := $(shell awk '/^feed=$(E2E_FEED_DESC)/{for(i=1;i<=NF;i++){if($$i ~ /^adapter=/){split($$i,a,"=");print a[2]}}}' out/e2e-addresses.txt))
	@echo "Oracle: $(ORACLE)"
	@echo "Adapter ($(E2E_FEED_DESC)): $(ADAPTER)"
	@echo "[3/4] Deploying TestPriceConsumer bound to adapter"
	ADAPTER=$(ADAPTER) forge script script/DeployTestConsumer.s.sol:DeployTestConsumer --rpc-url "$(RPC_URL)" --chain-id $(CHAIN_ID) --broadcast -vvvv
	@echo "[4/4] Starting operator bot (background)"
	@mkdir -p scripts/bot
	@nohup node scripts/bot/operators-bot.js --rpc "$(RPC_URL)" --oracle $(ORACLE) --feedDesc "$(E2E_FEED_DESC)" --interval $(E2E_INTERVAL_MS) > scripts/bot/operators-bot.log 2>&1 & echo $$! > scripts/bot/operators-bot.pid
	@echo "Bot started. PID: $$(cat scripts/bot/operators-bot.pid) | Log: scripts/bot/operators-bot.log"

e2e-clean:
	@if [ -f scripts/bot/operators-bot.pid ]; then \
	  PID=$$(cat scripts/bot/operators-bot.pid); \
	  echo "Killing bot PID $$PID"; \
	  kill $$PID || true; \
	  rm -f scripts/bot/operators-bot.pid; \
	else \
	  echo "No bot PID file found"; \
	fi
