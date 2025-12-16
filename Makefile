# ============================================================================
# Ethereum STARK Verifier - Makefile
# ============================================================================
# EVM Verification Only - Proof generation is done in prepare-proof repository
# ============================================================================

.PHONY: help setup clean test test-gas \
	test-program test-program-bootloader \
	test-fibonacci test-factorial test-fibonacci-bootloader test-factorial-bootloader \
	deploy-sepolia deploy-sepolia-dry deploy-sepolia-verified \
	verify-contracts-sepolia verify-proof-sepolia view-proof-sepolia \
	deploy-base-sepolia deploy-base-sepolia-dry deploy-base-sepolia-verified \
	verify-contracts-base-sepolia verify-proof-base-sepolia deploy-base

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------

SHELL := /bin/bash

# Load environment variables from .env if it exists
ifneq ($(wildcard .env),)
include .env
export
endif

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
	@echo "🧪 TESTING SPECIFIC PROGRAMS"
	@echo "  make test-program PROGRAM=fibonacci    - Test regular program proof"
	@echo "  make test-program-bootloader PROGRAM=factorial  - Test bootloader proof"
	@echo ""
	@echo "  Quick commands:"
	@echo "    make test-fibonacci                 - Test fibonacci"
	@echo "    make test-factorial                 - Test factorial"
	@echo "    make test-fibonacci-bootloader      - Test fibonacci bootloader"
	@echo "    make test-factorial-bootloader      - Test factorial bootloader"
	@echo ""
	@echo "🌐 DEPLOYMENT"
	@echo "  Sepolia Testnet:"
	@echo "    make deploy-sepolia-dry        - Simulate deployment"
	@echo "    make deploy-sepolia            - Deploy to Sepolia"
	@echo "    make deploy-sepolia-verified   - Deploy + auto-verify"
	@echo "    make verify-proof-sepolia      - Verify proof on-chain (for smaller proofs)"
	@echo "    make verify-proof-sepolia-split - Verify large bootloader proof using split approach"
	@echo "      (automatically handles trace decommitments, FRI decommitments, continuous pages, and main proof)"
	@echo ""
	@echo "  Base Network:"
	@echo "    make deploy-base-sepolia       - Deploy to Base Sepolia"
	@echo ""

# ----------------------------------------------------------------------------
# Setup & Maintenance
# ----------------------------------------------------------------------------

setup:
	@echo "🔧 Setting up project structure..."
	@mkdir -p examples
	@echo "✅ Setup complete!"
	@echo ""
	@echo "📝 Note: This repository only handles verification."
	@echo "   To generate proofs, use the prepare-proof repository."

clean:
	@echo "🧹 Cleaning generated files..."
	@rm -f input.json annotated_proof.json
	@rm -rf work/bootloader/input.json
	@echo "✅ Clean complete!"

# ----------------------------------------------------------------------------
# Testing
# ----------------------------------------------------------------------------

test:
	@echo "🧪 Running Forge tests..."
	@forge test

test-gas:
	@echo "🧪 Running Forge tests with gas report..."
	@forge test --gas-report

# Test specific program (fibonacci, factorial)
# Uses pre-prepared examples from examples/ directory
test-program:
	@if [ -z "$(PROGRAM)" ]; then \
		echo "❌ Error: PROGRAM not set. Use: make test-program PROGRAM=fibonacci"; \
		exit 1; \
	fi
	@if [ ! -f "examples/$(PROGRAM)/input.json" ]; then \
		echo "❌ Error: input.json not found in examples/$(PROGRAM)/"; \
		echo "Available examples: fibonacci, factorial"; \
		echo ""; \
		echo "To generate proof, use prepare-proof repository:"; \
		echo "  cd prepare-proof"; \
		echo "  make simple-flow PROGRAM=$(PROGRAM) LAYOUT=starknet"; \
		echo "  cp work/$(PROGRAM)-starknet/input.json ../ethereum_verifier/examples/$(PROGRAM)/"; \
		exit 1; \
	fi
	@echo "🧪 Testing program: $(PROGRAM)"
	@cp examples/$(PROGRAM)/input.json input.json
	@forge test --match-test test_VerifyProof
	@echo "✅ Test complete"

# Test bootloader program (factorial, fibonacci)
# Uses pre-prepared examples from examples/ directory
test-program-bootloader:
	@if [ -z "$(PROGRAM)" ]; then \
		echo "❌ Error: PROGRAM not set. Use: make test-program-bootloader PROGRAM=factorial"; \
		exit 1; \
	fi
	@if [ ! -f "examples/$(PROGRAM)-bootloader/input.json" ]; then \
		echo "❌ Error: input.json not found in examples/$(PROGRAM)-bootloader/"; \
		echo "Available bootloader examples: fibonacci-bootloader, factorial-bootloader"; \
		echo ""; \
		echo "To generate proof, use prepare-proof repository:"; \
		echo "  cd prepare-proof"; \
		echo "  make bootloader PROGRAM=$(PROGRAM) LAYOUT=starknet"; \
		echo "  cp work/bootloader-starknet/input.json ../ethereum_verifier/examples/$(PROGRAM)-bootloader/"; \
		exit 1; \
	fi
	@echo "🧪 Testing bootloader program: $(PROGRAM)"
	@mkdir -p work/bootloader
	@cp examples/$(PROGRAM)-bootloader/input.json work/bootloader/input.json
	@cp examples/$(PROGRAM)-bootloader/input.json input.json
	@forge test --match-test test_VerifyBootloaderProof
	@echo "✅ Test complete"

# Quick test commands for common programs
test-fibonacci:
	@$(MAKE) test-program PROGRAM=fibonacci

test-factorial:
	@$(MAKE) test-program PROGRAM=factorial

test-fibonacci-bootloader:
	@$(MAKE) test-program-bootloader PROGRAM=fibonacci

test-factorial-bootloader:
	@$(MAKE) test-program-bootloader PROGRAM=factorial

# ----------------------------------------------------------------------------
# Deployment - Sepolia Testnet
# ----------------------------------------------------------------------------

deploy-sepolia-dry:
	@echo "🔍 Dry run deployment to Sepolia..."
	@if [ ! -f .env ]; then \
		echo "❌ Error: .env not found. Copy .env.example"; \
		exit 1; \
	fi
	@set -a && source .env && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$SEPOLIA_RPC_URL \
		-vvvv

deploy-sepolia:
	@echo "🚀 Deploying to Sepolia testnet..."
	@if [ ! -f .env ]; then \
		echo "❌ Error: .env not found. Copy .env.example"; \
		exit 1; \
	fi
	@set -a && source .env && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$SEPOLIA_RPC_URL \
		--broadcast \
		-vvvv
	@echo "✅ Deployment complete! Verify with: make verify-contracts-sepolia"

deploy-sepolia-verified:
	@echo "🚀 Deploying to Sepolia with verification..."
	@if [ ! -f .env ]; then \
		echo "❌ Error: .env not found"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && \
	if [ -z "$$ETHERSCAN_API_KEY" ]; then \
		echo "❌ Error: ETHERSCAN_API_KEY not set in .env"; \
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
	@if [ ! -f .env ] || [ ! -f deployment-addresses.json ]; then \
		echo "❌ Error: Missing .env or deployment-addresses.json"; \
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
	@if [ ! -f .env ]; then \
		echo "❌ Error: .env not found. Copy .env.example and configure it."; \
		exit 1; \
	fi
	@if [ ! -f deployment-addresses.json ]; then \
		echo "❌ Error: deployment-addresses.json not found. Run 'make deploy-sepolia' first."; \
		exit 1; \
	fi
	@if [ ! -f input.json ]; then \
		echo "❌ Error: input.json not found."; \
		echo ""; \
		echo "You need to copy input.json from examples/ or prepare-proof repository:"; \
		echo "  make test-program PROGRAM=fibonacci  # This will copy from examples/"; \
		echo "  # OR"; \
		echo "  cp examples/fibonacci/input.json input.json"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/VerifyProof.s.sol:VerifyProofScript \
		--rpc-url $$SEPOLIA_RPC_URL \
		--broadcast \
		-vvvv

verify-proof-sepolia-split:
	@echo "🔍 Verifying proof using split approach (for large bootloader proofs)..."
	@if [ ! -f .env ]; then \
		echo "❌ Error: .env not found. Copy .env.example and configure it."; \
		exit 1; \
	fi
	@if [ ! -f deployment-addresses.json ]; then \
		echo "❌ Error: deployment-addresses.json not found. Run 'make deploy-sepolia' first."; \
		exit 1; \
	fi
	@if [ ! -f work/bootloader/annotated_proof.json ] && [ ! -f annotated_proof.json ]; then \
		echo "❌ Error: annotated_proof.json not found."; \
		echo "Expected locations: work/bootloader/annotated_proof.json or annotated_proof.json"; \
		exit 1; \
	fi
	@FACT_TOPOLOGIES=$$([ -f work/bootloader/fact_topologies.json ] && echo "work/bootloader/fact_topologies.json" || \
		[ -f bootloader/fact_topologies.json ] && echo "bootloader/fact_topologies.json" || \
		[ -f fact_topologies.json ] && echo "fact_topologies.json" || echo ""); \
	if [ -z "$$FACT_TOPOLOGIES" ]; then \
		echo "❌ Error: fact_topologies.json not found."; \
		echo "Expected locations: work/bootloader/fact_topologies.json, bootloader/fact_topologies.json, or fact_topologies.json"; \
		exit 1; \
	fi; \
	echo "Using fact_topologies.json from: $$FACT_TOPOLOGIES"
	@echo "Building verify..."
	@cd scripts/verify_proof_split && cargo build --release
	@FACT_TOPOLOGIES=$$([ -f work/bootloader/fact_topologies.json ] && echo "work/bootloader/fact_topologies.json" || \
		[ -f bootloader/fact_topologies.json ] && echo "bootloader/fact_topologies.json" || \
		[ -f fact_topologies.json ] && echo "fact_topologies.json" || echo ""); \
	set -a && source .env.deploy && set +a && \
		ANNOTATED_PROOF=$$([ -f work/bootloader/annotated_proof.json ] && echo "work/bootloader/annotated_proof.json" || echo "annotated_proof.json") \
		FACT_TOPOLOGIES=$$FACT_TOPOLOGIES \
		cd /home/michal/Documents/Ethereum_verifier && ./target/release/verify

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
	@if [ ! -f .env ]; then \
		echo "❌ Error: .env not found"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$BASE_SEPOLIA_RPC_URL \
		-vvvv

deploy-base-sepolia:
	@echo "🚀 Deploying to Base Sepolia testnet..."
	@if [ ! -f .env ]; then \
		echo "❌ Error: .env not found"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$BASE_SEPOLIA_RPC_URL \
		--broadcast \
		-vvvv
	@echo "✅ Deployment complete! Verify with: make verify-contracts-base-sepolia"

deploy-base-sepolia-verified:
	@echo "🚀 Deploying to Base Sepolia with verification..."
	@if [ ! -f .env ]; then \
		echo "❌ Error: .env not found"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && \
	if [ -z "$$BASESCAN_API_KEY" ]; then \
		echo "❌ Error: BASESCAN_API_KEY not set in .env"; \
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
	@if [ ! -f .env ] || [ ! -f deployment-addresses.json ]; then \
		echo "❌ Error: Missing .env or deployment-addresses.json"; \
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
	@if [ ! -f .env ] || [ ! -f deployment-addresses.json ] || [ ! -f input.json ]; then \
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
	@if [ ! -f .env ]; then \
		echo "❌ Error: .env not found"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$BASE_RPC_URL \
		--broadcast \
		-vvvv
