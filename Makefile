# ============================================================================
# Ethereum STARK Verifier - Makefile
# ============================================================================
# Simple Cairo proofs + Bootloader proofs + Deployment
# ============================================================================

.PHONY: help setup clean test \
	simple-flow cairo-run prove prove-only verify prepare \
	bootloader bootloader-pie bootloader-run bootloader-prove bootloader-verify bootloader-prepare bootloader-prepare-only \
	test-gas deploy-sepolia deploy-sepolia-dry deploy-sepolia-verified \
	verify-contracts-sepolia verify-proof-sepolia view-proof-sepolia \
	deploy-base-sepolia deploy-base-sepolia-dry deploy-base-sepolia-verified \
	verify-contracts-base-sepolia verify-proof-base-sepolia deploy-base \
	copy-cairo-files benchmark flow all bootloader-flow bootloader-all create-pie bootloader-cairo-run

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------

SHELL := /bin/bash

# Load environment variables from .env
include .env
export

# ----------------------------------------------------------------------------
# Help - Main entry point
# ----------------------------------------------------------------------------

help:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║        Ethereum STARK Verifier - Available Commands            ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "📦 SETUP & TESTING"
	@echo "  make setup                     - Initialize project structure"
	@echo "  make test                      - Run all Forge tests"
	@echo "  make test-gas                  - Run tests with gas report"
	@echo "  make clean                     - Clean generated files"
	@echo ""
	@echo "🔹 SIMPLE CAIRO PROOF (for testing)"
	@echo "  make simple-flow PROGRAM=fibonacci   - Complete simple proof flow"
	@echo "  make cairo-run PROGRAM=fibonacci     - Run Cairo program"
	@echo "  make prove PROGRAM=fibonacci         - Generate STARK proof"
	@echo "  make verify PROGRAM=fibonacci        - Verify proof with Stone"
	@echo "  make prepare PROGRAM=fibonacci       - Prepare proof for EVM"
	@echo ""
	@echo "🚀 BOOTLOADER PROOF (for GPS Statement Verifier)"
	@echo "  make bootloader PROGRAM=factorial    - 🎯 Complete bootloader flow (ONE COMMAND!)"
	@echo "  make bootloader-pie PROGRAM=factorial     - Step 1: Create PIE"
	@echo "  make bootloader-run PROGRAM=factorial     - Step 2: Run bootloader"
	@echo "  make bootloader-prove PROGRAM=factorial   - Step 3: Generate proof"
	@echo "  make bootloader-prepare PROGRAM=factorial - Step 4: Prepare for EVM"
	@echo ""
	@echo "🌐 DEPLOYMENT"
	@echo "  Sepolia Testnet:"
	@echo "    make deploy-sepolia-dry        - Simulate deployment"
	@echo "    make deploy-sepolia            - Deploy to Sepolia"
	@echo "    make deploy-sepolia-verified   - Deploy + auto-verify"
	@echo "    make verify-proof-sepolia      - Verify proof on-chain"
	@echo ""
	@echo "  Base Network:"
	@echo "    make deploy-base-sepolia       - Deploy to Base Sepolia"
	@echo "    make deploy-base               - Deploy to Base Mainnet (⚠️ CAUTION)"
	@echo ""
	@echo "🔧 UTILITIES"
	@echo "  make benchmark                 - Run performance benchmarks"
	@echo "  make copy-cairo-files PROGRAM=fibonacci - Copy files from stone-prover"
	@echo ""

# ----------------------------------------------------------------------------
# Setup & Maintenance
# ----------------------------------------------------------------------------

setup:
	@echo "🔧 Setting up project structure..."
	@mkdir -p $(WORK_DIR)
	@mkdir -p bootloader
	@mkdir -p examples
	@if [ ! -f .env ]; then cp .env.example .env; echo "✓ Created .env file"; fi
	@echo "📦 Building Rust tools..."
	@cargo build --release --workspace 2>&1 | tail -1
	@echo "✅ Setup complete!"

clean:
	@echo "🧹 Cleaning generated files..."
	@rm -rf $(WORK_DIR)/*
	@rm -rf bootloader/*.bin bootloader/*_input.json bootloader/*_public_input.json
	@rm -f annotated_proof.json input.json
	@echo "✅ Clean complete!"

# ----------------------------------------------------------------------------
# Simple Cairo Proof Workflow (for testing individual programs)
# ----------------------------------------------------------------------------

# Complete simple proof flow in one command
simple-flow:
	@if [ -z "$(PROGRAM)" ]; then echo "❌ Error: PROGRAM not set. Use: make simple-flow PROGRAM=fibonacci"; exit 1; fi
	@echo "🚀 Starting simple proof flow for: $(PROGRAM)"
	@$(MAKE) setup
	@if [ -f "$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_private_input.json" ]; then \
		echo "📁 Cairo files found, skipping cairo-run..."; \
		$(MAKE) prove-only PROGRAM=$(PROGRAM); \
	else \
		echo "▶️  Running Cairo program..."; \
		$(MAKE) prove PROGRAM=$(PROGRAM); \
	fi
	@$(MAKE) prepare PROGRAM=$(PROGRAM)
	@echo ""
	@echo "✅ Simple proof flow complete!"
	@echo "   📄 Proof: $(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_proof.json"
	@echo "   📄 EVM Input: $(WORK_DIR)/$(PROGRAM)/input.json"
	@echo "   ▶️  Run 'make test' to verify the proof"

# Step 1: Run Cairo program to generate trace/memory
cairo-run:
	@if [ -z "$(PROGRAM)" ]; then echo "❌ Error: PROGRAM not set"; exit 1; fi
	@echo "▶️  Running Cairo program: $(PROGRAM)"
	@mkdir -p $(WORK_DIR)/$(PROGRAM)
	$(CAIRO_RUN) \
		--program=examples/$(PROGRAM)/$(PROGRAM)_compiled.json \
		--layout=starknet \
		--program_input=examples/$(PROGRAM)/$(PROGRAM)_input.json \
		--air_public_input=$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_public_input.json \
		--air_private_input=$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_private_input.json \
		--trace_file=$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_trace.bin \
		--memory_file=$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_memory.bin \
		--print_output \
		--proof_mode

# Step 2: Generate STARK proof (with Cairo run)
prove: cairo-run
	@$(MAKE) prove-only PROGRAM=$(PROGRAM)

# Step 2b: Generate STARK proof (skip Cairo run)
prove-only:
	@if [ -z "$(PROGRAM)" ]; then echo "❌ Error: PROGRAM not set"; exit 1; fi
	@if [ ! -f "$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_private_input.json" ]; then \
		echo "❌ Error: Cairo files not found. Run 'make cairo-run PROGRAM=$(PROGRAM)' first"; \
		exit 1; \
	fi
	@echo "🔐 Generating STARK proof for: $(PROGRAM)"
	$(CPU_AIR_PROVER) \
		--out_file=$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_proof.json \
		--private_input_file=$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_private_input.json \
		--public_input_file=$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_public_input.json \
		--prover_config_file=$(PROVER_CONFIG) \
		--parameter_file=$(PROVER_PARAMS) \
		--generate_annotations true
	@echo "✅ Proof generated: $(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_proof.json"

# Step 3: Verify proof with Stone verifier
verify:
	@if [ -z "$(PROGRAM)" ]; then echo "❌ Error: PROGRAM not set"; exit 1; fi
	@echo "🔍 Verifying STARK proof for: $(PROGRAM)"
	$(CPU_AIR_VERIFIER) \
		--in_file=$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_proof.json \
		--extra_output_file=$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_extra_output.json \
		--annotation_file=$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_annotation_file.json
	@echo "✅ Verification complete!"

# Step 4: Prepare proof for EVM
prepare: verify
	@echo "📦 Preparing proof for EVM..."
	$(STARK_EVM_ADAPTER) gen-annotated-proof \
		--stone-proof-file $(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_proof.json \
		--stone-annotation-file $(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_annotation_file.json \
		--stone-extra-annotation-file $(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_extra_output.json \
		--output $(WORK_DIR)/$(PROGRAM)/annotated_proof.json
	@cargo run --package prepare-input --bin prepare-input \
		$(WORK_DIR)/$(PROGRAM)/annotated_proof.json \
		$(WORK_DIR)/$(PROGRAM)/input.json
	@ln -sf $(WORK_DIR)/$(PROGRAM)/annotated_proof.json annotated_proof.json
	@ln -sf $(WORK_DIR)/$(PROGRAM)/input.json input.json
	@echo "✅ EVM proof ready: $(WORK_DIR)/$(PROGRAM)/input.json"

# ----------------------------------------------------------------------------
# Bootloader Proof Workflow (for GPS Statement Verifier)
# ----------------------------------------------------------------------------

# 🎯 ONE COMMAND - Complete bootloader flow!
bootloader:
	@if [ -z "$(PROGRAM)" ]; then echo "❌ Error: PROGRAM not set. Use: make bootloader PROGRAM=factorial"; exit 1; fi
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║         🚀 Starting BOOTLOADER PROOF workflow                  ║"
	@echo "║            Program: $(PROGRAM)                                 ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@# Step 1: Create PIE if needed
	@if [ ! -f "bootloader/$(PROGRAM).zip" ]; then \
		echo "📦 Step 1/4: Creating PIE..."; \
		$(MAKE) bootloader-pie PROGRAM=$(PROGRAM); \
	else \
		echo "✓ Step 1/4: PIE already exists"; \
	fi
	@# Step 2: Run bootloader if needed
	@if [ ! -f "bootloader/$(PROGRAM)_private_input.json" ]; then \
		echo "▶️  Step 2/4: Running bootloader..."; \
		$(MAKE) bootloader-run PROGRAM=$(PROGRAM); \
	else \
		echo "✓ Step 2/4: Bootloader execution files exist"; \
	fi
	@# Step 3: Generate proof if needed
	@if [ ! -f "$(WORK_DIR)/bootloader/$(PROGRAM)_proof.json" ]; then \
		echo "🔐 Step 3/4: Generating proof..."; \
		$(MAKE) bootloader-prove PROGRAM=$(PROGRAM); \
	else \
		echo "✓ Step 3/4: Proof already exists"; \
	fi
	@# Step 4: Always prepare (this is fast)
	@echo "📦 Step 4/4: Preparing for EVM..."
	@$(MAKE) bootloader-prepare-only PROGRAM=$(PROGRAM)
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                  ✅ BOOTLOADER PROOF READY!                    ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo "📄 Files:"
	@echo "   PIE: bootloader/$(PROGRAM).zip"
	@echo "   Proof: $(WORK_DIR)/bootloader/$(PROGRAM)_proof.json"
	@echo "   EVM Input: $(WORK_DIR)/bootloader/input.json"
	@echo ""
	@echo "▶️  Next step: make test-gas"

# Step 1: Generate PIE from a Cairo program
bootloader-pie:
	@if [ -z "$(PROGRAM)" ]; then echo "❌ Error: PROGRAM not set"; exit 1; fi
	@if [ ! -f "examples/$(PROGRAM)/$(PROGRAM)_compiled.json" ]; then \
		echo "❌ Error: Program not found: examples/$(PROGRAM)/$(PROGRAM)_compiled.json"; \
		exit 1; \
	fi
	@echo "📦 Creating PIE from $(PROGRAM)..."
	@mkdir -p bootloader
	@cd $(STONE_PROVER_DIR) && \
		source $(VENV_NAME)/bin/activate && \
		cairo-run \
			--cairo_pie_output=$(CURDIR)/bootloader/$(PROGRAM).zip \
			--program=$(CURDIR)/examples/$(PROGRAM)/$(PROGRAM)_compiled.json \
			--layout=starknet \
			--program_input=$(CURDIR)/examples/$(PROGRAM)/$(PROGRAM)_input.json
	@echo "📝 Creating bootloader_input.json..."
	@python3 scripts/create_bootloader_input.py \
		examples/$(PROGRAM)/$(PROGRAM)_compiled.json \
		examples/$(PROGRAM)/$(PROGRAM)_input.json \
		bootloader/bootloader_input.json
	@echo "✅ PIE created: bootloader/$(PROGRAM).zip"

# Step 2: Run bootloader with PIE
bootloader-run:
	@if [ -z "$(PROGRAM)" ]; then echo "❌ Error: PROGRAM not set"; exit 1; fi
	@if [ ! -f "bootloader/bootloader_input.json" ]; then \
		echo "❌ Error: bootloader_input.json not found. Run 'make bootloader-pie PROGRAM=$(PROGRAM)' first"; \
		exit 1; \
	fi
	@echo "▶️  Running bootloader for: $(PROGRAM)"
	@mkdir -p bootloader
	@if [ -n "$(CAIRO_LANG_DIR)" ] && [ -d "$(CAIRO_LANG_DIR)" ]; then \
		echo "   Using cairo-lang from: $(CAIRO_LANG_DIR)"; \
		cd $(CAIRO_LANG_DIR) && \
		source $(CAIRO_LANG_VENV)/bin/activate && \
		python src/starkware/cairo/lang/scripts/cairo-run \
			--program=$(CURDIR)/bootloader/bootloader.json \
			--layout=starknet \
			--program_input=$(CURDIR)/bootloader/bootloader_input.json \
			--print_output \
			--print_info \
			--air_public_input=$(CURDIR)/bootloader/$(PROGRAM)_public_input.json \
			--air_private_input=$(CURDIR)/bootloader/$(PROGRAM)_private_input.json \
			--trace_file=$(CURDIR)/bootloader/$(PROGRAM)_trace.bin \
			--memory_file=$(CURDIR)/bootloader/$(PROGRAM)_memory.bin \
			--proof_mode; \
	else \
		echo "   Using stone-prover"; \
		cd $(STONE_PROVER_DIR) && \
		source $(VENV_NAME)/bin/activate && \
		python src/starkware/cairo/lang/scripts/cairo-run \
			--program=$(CURDIR)/bootloader/bootloader.json \
			--layout=starknet \
			--program_input=$(CURDIR)/bootloader/bootloader_input.json \
			--print_output \
			--print_info \
			--air_public_input=$(CURDIR)/bootloader/$(PROGRAM)_public_input.json \
			--air_private_input=$(CURDIR)/bootloader/$(PROGRAM)_private_input.json \
			--trace_file=$(CURDIR)/bootloader/$(PROGRAM)_trace.bin \
			--memory_file=$(CURDIR)/bootloader/$(PROGRAM)_memory.bin \
			--proof_mode; \
	fi
	@echo "✅ Bootloader execution complete"

# Step 3: Generate STARK proof from bootloader
bootloader-prove:
	@if [ -z "$(PROGRAM)" ]; then echo "❌ Error: PROGRAM not set"; exit 1; fi
	@if [ ! -f "bootloader/$(PROGRAM)_private_input.json" ]; then \
		echo "❌ Error: Bootloader files not found. Run 'make bootloader-run PROGRAM=$(PROGRAM)' first"; \
		exit 1; \
	fi
	@echo "🔐 Generating STARK proof from bootloader for: $(PROGRAM)"
	@mkdir -p $(WORK_DIR)/bootloader
	$(CPU_AIR_PROVER) \
		--out_file=$(WORK_DIR)/bootloader/$(PROGRAM)_proof.json \
		--private_input_file=bootloader/$(PROGRAM)_private_input.json \
		--public_input_file=bootloader/$(PROGRAM)_public_input.json \
		--prover_config_file=$(PROVER_CONFIG) \
		--parameter_file=$(PROVER_PARAMS) \
		--generate_annotations true
	@echo "✅ Bootloader proof generated: $(WORK_DIR)/bootloader/$(PROGRAM)_proof.json"

# Step 4: Verify bootloader proof
bootloader-verify:
	@if [ -z "$(PROGRAM)" ]; then echo "❌ Error: PROGRAM not set"; exit 1; fi
	@echo "🔍 Verifying bootloader STARK proof for: $(PROGRAM)"
	$(CPU_AIR_VERIFIER) \
		--in_file=$(WORK_DIR)/bootloader/$(PROGRAM)_proof.json \
		--extra_output_file=$(WORK_DIR)/bootloader/$(PROGRAM)_extra_output.json \
		--annotation_file=$(WORK_DIR)/bootloader/$(PROGRAM)_annotation_file.json
	@echo "✅ Bootloader verification complete!"

# Step 5: Prepare bootloader proof for EVM
bootloader-prepare: bootloader-verify bootloader-prepare-only

bootloader-prepare-only:
	@echo "📦 Preparing bootloader proof for EVM..."
	$(STARK_EVM_ADAPTER) gen-annotated-proof \
		--stone-proof-file $(WORK_DIR)/bootloader/$(PROGRAM)_proof.json \
		--stone-annotation-file $(WORK_DIR)/bootloader/$(PROGRAM)_annotation_file.json \
		--stone-extra-annotation-file $(WORK_DIR)/bootloader/$(PROGRAM)_extra_output.json \
		--output $(WORK_DIR)/bootloader/annotated_proof.json
	@cargo run --package prepare-input --bin prepare-input \
		$(WORK_DIR)/bootloader/annotated_proof.json \
		$(WORK_DIR)/bootloader/input.json
	@ln -sf $(WORK_DIR)/bootloader/annotated_proof.json annotated_proof.json
	@ln -sf $(WORK_DIR)/bootloader/input.json input.json
	@echo "✅ Bootloader EVM proof ready: $(WORK_DIR)/bootloader/input.json"

# ----------------------------------------------------------------------------
# Testing
# ----------------------------------------------------------------------------

test:
	@echo "🧪 Running Forge tests..."
	@forge test

test-gas:
	@echo "🧪 Running Forge tests with gas report..."
	@forge test --gas-report

# ----------------------------------------------------------------------------
# Deployment - Sepolia Testnet
# ----------------------------------------------------------------------------

deploy-sepolia-dry:
	@echo "🔍 Dry run deployment to Sepolia..."
	@if [ ! -f .env.deploy ]; then \
		echo "❌ Error: .env.deploy not found. Copy .env.deploy.example"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$SEPOLIA_RPC_URL \
		-vvvv

deploy-sepolia:
	@echo "🚀 Deploying to Sepolia testnet..."
	@if [ ! -f .env.deploy ]; then \
		echo "❌ Error: .env.deploy not found. Copy .env.deploy.example"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$SEPOLIA_RPC_URL \
		--broadcast \
		-vvvv
	@echo "✅ Deployment complete! Verify with: make verify-contracts-sepolia"

deploy-sepolia-verified:
	@echo "🚀 Deploying to Sepolia with verification..."
	@if [ ! -f .env.deploy ]; then \
		echo "❌ Error: .env.deploy not found"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && \
	if [ -z "$$ETHERSCAN_API_KEY" ]; then \
		echo "❌ Error: ETHERSCAN_API_KEY not set in .env.deploy"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$SEPOLIA_RPC_URL \
		--broadcast \
		--verify \
		--etherscan-api-key $$ETHERSCAN_API_KEY \
		-vvvv

verify-contracts-sepolia:
	@echo "🔍 Verifying contracts on Etherscan..."
	@if [ ! -f .env.deploy ] || [ ! -f deployment-addresses.json ]; then \
		echo "❌ Error: Missing .env.deploy or deployment-addresses.json"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && \
	VERIFIER=$$(cat deployment-addresses.json | jq -r '.verifier') && \
	forge verify-contract $$VERIFIER \
		src/layout_starknet/CpuVerifier.sol:CpuVerifier \
		--chain sepolia \
		--etherscan-api-key $$ETHERSCAN_API_KEY \
		--watch

verify-proof-sepolia:
	@echo "🔍 Verifying proof on deployed Sepolia contract..."
	@if [ ! -f .env.deploy ] || [ ! -f deployment-addresses.json ] || [ ! -f input.json ]; then \
		echo "❌ Error: Missing required files"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/VerifyProof.s.sol:VerifyProofScript \
		--rpc-url $$SEPOLIA_RPC_URL \
		--broadcast \
		-vvvv

view-proof-sepolia:
	@echo "👁️  Viewing proof verification result (read-only)..."
	@if [ ! -f deployment-addresses.json ]; then \
		echo "❌ Error: deployment-addresses.json not found"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/VerifyProof.s.sol:VerifyProofScript \
		--rpc-url $$SEPOLIA_RPC_URL \
		-vvv

# ----------------------------------------------------------------------------
# Deployment - Base Network
# ----------------------------------------------------------------------------

deploy-base-sepolia-dry:
	@echo "🔍 Dry run deployment to Base Sepolia..."
	@if [ ! -f .env.deploy ]; then \
		echo "❌ Error: .env.deploy not found"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$BASE_SEPOLIA_RPC_URL \
		-vvvv

deploy-base-sepolia:
	@echo "🚀 Deploying to Base Sepolia testnet..."
	@if [ ! -f .env.deploy ]; then \
		echo "❌ Error: .env.deploy not found"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$BASE_SEPOLIA_RPC_URL \
		--broadcast \
		-vvvv
	@echo "✅ Deployment complete! Verify with: make verify-contracts-base-sepolia"

deploy-base-sepolia-verified:
	@echo "🚀 Deploying to Base Sepolia with verification..."
	@if [ ! -f .env.deploy ]; then \
		echo "❌ Error: .env.deploy not found"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && \
	if [ -z "$$BASESCAN_API_KEY" ]; then \
		echo "❌ Error: BASESCAN_API_KEY not set in .env.deploy"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$BASE_SEPOLIA_RPC_URL \
		--broadcast \
		--verify \
		--verifier-url https://api-sepolia.basescan.org/api \
		--etherscan-api-key $$BASESCAN_API_KEY \
		-vvvv

verify-contracts-base-sepolia:
	@echo "🔍 Verifying contracts on Basescan..."
	@if [ ! -f .env.deploy ] || [ ! -f deployment-addresses.json ]; then \
		echo "❌ Error: Missing .env.deploy or deployment-addresses.json"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && \
	VERIFIER=$$(cat deployment-addresses.json | jq -r '.verifier') && \
	forge verify-contract $$VERIFIER \
		src/layout_starknet/CpuVerifier.sol:CpuVerifier \
		--chain-id 84532 \
		--verifier-url https://api-sepolia.basescan.org/api \
		--etherscan-api-key $$BASESCAN_API_KEY \
		--watch

verify-proof-base-sepolia:
	@echo "🔍 Verifying proof on deployed Base Sepolia contract..."
	@if [ ! -f .env.deploy ] || [ ! -f deployment-addresses.json ] || [ ! -f input.json ]; then \
		echo "❌ Error: Missing required files"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/VerifyProof.s.sol:VerifyProofScript \
		--rpc-url $$BASE_SEPOLIA_RPC_URL \
		--broadcast \
		-vvvv

deploy-base:
	@echo "⚠️  WARNING: Deploying to Base MAINNET!"
	@echo "Make sure you have enough ETH!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "Deployment cancelled."; \
		exit 1; \
	fi
	@if [ ! -f .env.deploy ]; then \
		echo "❌ Error: .env.deploy not found"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$BASE_RPC_URL \
		--broadcast \
		-vvvv

# ----------------------------------------------------------------------------
# Utilities
# ----------------------------------------------------------------------------

copy-cairo-files:
	@if [ -z "$(PROGRAM)" ] || [ -z "$(STONE_PROVER_DIR)" ]; then \
		echo "❌ Error: PROGRAM or STONE_PROVER_DIR not set"; \
		exit 1; \
	fi
	@echo "📁 Copying Cairo files from stone-prover..."
	@mkdir -p $(WORK_DIR)/$(PROGRAM)
	@cp $(STONE_PROVER_DIR)/e2e_test/CairoZero/$(PROGRAM)_*.json $(WORK_DIR)/$(PROGRAM)/ 2>/dev/null || true
	@cp $(STONE_PROVER_DIR)/e2e_test/CairoZero/$(PROGRAM)_*.bin $(WORK_DIR)/$(PROGRAM)/ 2>/dev/null || true
	@echo "✅ Files copied!"

benchmark:
	@echo "⚡ Running benchmarks..."
	@./scripts/benchmark.sh 10 100 1000 10000 100000 1000000

# ----------------------------------------------------------------------------
# Backward compatibility aliases (deprecated)
# ----------------------------------------------------------------------------

# Old targets that still work but redirect to new names
flow: simple-flow
all: simple-flow test-gas
bootloader-flow: bootloader
bootloader-all: bootloader
create-pie: bootloader-pie
bootloader-cairo-run: bootloader-run
