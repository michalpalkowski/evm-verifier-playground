.PHONY: help setup clean prove verify test all

# Use bash as shell
SHELL := /bin/bash

# Load environment variables
include .env
export

# Default target
help:
	@echo "Ethereum STARK Verifier - Build Commands"
	@echo ""
	@echo "Setup:"
	@echo "  make setup          - Create directories and copy .env.example"
	@echo ""
	@echo "Proof Generation:"
	@echo "  make cairo-run PROGRAM=fibonacci  - Run Cairo program (needs venv)"
	@echo "  make prove PROGRAM=fibonacci      - Cairo run + generate proof"
	@echo "  make prove-only PROGRAM=fibonacci - Generate proof (skip cairo-run)"
	@echo "  make verify PROGRAM=fibonacci     - Verify proof with stone verifier"
	@echo "  make prepare PROGRAM=fibonacci    - Prepare proof for EVM"
	@echo ""
	@echo "Testing:"
	@echo "  make test           - Run Forge tests"
	@echo "  make test-gas       - Run Forge tests with gas report"
	@echo ""
	@echo "Complete Workflow:"
	@echo "  make all PROGRAM=fibonacci        - Run entire pipeline (with cairo-run)"
	@echo "  make all-skip-cairo PROGRAM=fibonacci - Run pipeline (skip cairo-run)"
	@echo ""
	@echo "Utilities:"
	@echo "  make clean          - Clean generated files"
	@echo "  make copy-cairo-files PROGRAM=fibonacci - Copy files from stone-prover"
	@echo "  make calc-fri-steps PROGRAM=fibonacci   - Calculate optimal FRI steps"
	@echo "  make benchmark      - Run benchmark tests (fibonacci)"
	@echo ""
	@echo "Deployment (Sepolia):"
	@echo "  make deploy-sepolia-dry       - Simulate deployment to Sepolia"
	@echo "  make deploy-sepolia           - Deploy to Sepolia (no verification)"
	@echo "  make deploy-sepolia-verified  - Deploy + auto-verify on Etherscan"
	@echo "  make verify-contracts-sepolia - Verify contracts after deployment"
	@echo "  make verify-proof-sepolia     - Verify proof on deployed contract"
	@echo "  make view-proof-sepolia       - View proof result (read-only)"
	@echo ""
	@echo "Deployment (Base):"
	@echo "  make deploy-base-sepolia-dry       - Simulate deployment to Base Sepolia"
	@echo "  make deploy-base-sepolia           - Deploy to Base Sepolia (testnet)"
	@echo "  make deploy-base-sepolia-verified  - Deploy + auto-verify on Basescan"
	@echo "  make verify-contracts-base-sepolia - Verify contracts after deployment"
	@echo "  make verify-proof-base-sepolia     - Verify proof on deployed contract"
	@echo "  make deploy-base                   - Deploy to Base Mainnet (⚠️  CAUTION)"

# Setup project
setup:
	@echo "Setting up project structure..."
	@mkdir -p $(WORK_DIR)
	@mkdir -p examples
	@if [ ! -f .env ]; then cp .env.example .env; echo "Created .env file"; fi
	@echo "Building tools..."
	@cargo build --release --workspace 2>&1 | tail -1
	@echo "Setup complete!"

# Clean generated files
clean:
	@echo "Cleaning generated files..."
	@rm -rf $(WORK_DIR)/*
	@rm -f annotated_proof.json input.json
	@echo "Clean complete!"

# Generate Cairo trace and memory
cairo-run:
	@if [ -z "$(PROGRAM)" ]; then echo "Error: PROGRAM not set. Use: make cairo-run PROGRAM=fibonacci"; exit 1; fi
	@echo "Running Cairo program: $(PROGRAM)"
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

# Generate STARK proof (with Cairo run)
prove: cairo-run
	@$(MAKE) prove-only PROGRAM=$(PROGRAM)

# Calculate optimal FRI steps
calc-fri-steps:
	@if [ -z "$(PROGRAM)" ]; then echo "Error: PROGRAM not set"; exit 1; fi
	@if [ -f "$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_public_input.json" ]; then \
		echo "Calculating optimal FRI steps..."; \
		./target/release/calculate-fri-steps \
			--params-file $(PROVER_PARAMS) \
			--public-input $(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_public_input.json; \
	else \
		echo "Skipping FRI calculation (no public_input yet)"; \
	fi

# Generate STARK proof (skip Cairo run)
prove-only:
	@if [ -z "$(PROGRAM)" ]; then echo "Error: PROGRAM not set. Use: make prove-only PROGRAM=fibonacci"; exit 1; fi
	@if [ ! -f "$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_private_input.json" ]; then \
		echo "Error: Cairo files not found. Run 'make cairo-run PROGRAM=$(PROGRAM)' first or copy files from stone-prover"; \
		exit 1; \
	fi
	@$(MAKE) calc-fri-steps PROGRAM=$(PROGRAM)
	@echo "Generating STARK proof for: $(PROGRAM)"
	$(CPU_AIR_PROVER) \
		--out_file=$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_proof.json \
		--private_input_file=$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_private_input.json \
		--public_input_file=$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_public_input.json \
		--prover_config_file=$(PROVER_CONFIG) \
		--parameter_file=$(PROVER_PARAMS) \
		--generate_annotations true
	@echo "Proof generated: $(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_proof.json"

# Verify proof with Stone verifier
verify:
	@if [ -z "$(PROGRAM)" ]; then echo "Error: PROGRAM not set. Use: make verify PROGRAM=fibonacci"; exit 1; fi
	@echo "Verifying STARK proof for: $(PROGRAM)"
	$(CPU_AIR_VERIFIER) \
		--in_file=$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_proof.json \
		--extra_output_file=$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_extra_output.json \
		--annotation_file=$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_annotation_file.json
	@echo "Verification complete!"

# Prepare proof for EVM
prepare: verify
	@echo "Preparing annotated proof for EVM..."
	$(STARK_EVM_ADAPTER) gen-annotated-proof \
		--stone-proof-file $(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_proof.json \
		--stone-annotation-file $(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_annotation_file.json \
		--stone-extra-annotation-file $(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_extra_output.json \
		--output $(WORK_DIR)/$(PROGRAM)/annotated_proof.json
	@echo "Generating EVM input..."
	@cargo run --package prepare-input --bin prepare-input \
		$(WORK_DIR)/$(PROGRAM)/annotated_proof.json \
		$(WORK_DIR)/$(PROGRAM)/input.json
	@ln -sf $(WORK_DIR)/$(PROGRAM)/annotated_proof.json annotated_proof.json
	@ln -sf $(WORK_DIR)/$(PROGRAM)/input.json input.json
	@echo "EVM proof ready: $(WORK_DIR)/$(PROGRAM)/input.json"

# Run forge tests
test:
	@forge test

# Run forge tests with gas report
test-gas:
	@forge test --gas-report

# Complete workflow (with cairo-run)
all: setup prove prepare test-gas
	@echo ""
	@echo "✓ Complete workflow finished!"
	@echo "  Proof: $(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_proof.json"
	@echo "  EVM Input: $(WORK_DIR)/$(PROGRAM)/input.json"

# Complete workflow (skip cairo-run)
all-skip-cairo: setup prove-only prepare test-gas
	@echo ""
	@echo "✓ Complete workflow finished!"
	@echo "  Proof: $(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_proof.json"
	@echo "  EVM Input: $(WORK_DIR)/$(PROGRAM)/input.json"

# Copy Cairo files from stone-prover
copy-cairo-files:
	@if [ -z "$(PROGRAM)" ]; then echo "Error: PROGRAM not set"; exit 1; fi
	@if [ -z "$(STONE_PROVER_DIR)" ]; then echo "Error: STONE_PROVER_DIR not set in .env"; exit 1; fi
	@echo "Copying Cairo files from stone-prover..."
	@mkdir -p $(WORK_DIR)/$(PROGRAM)
	@cp $(STONE_PROVER_DIR)/e2e_test/CairoZero/$(PROGRAM)_public_input.json $(WORK_DIR)/$(PROGRAM)/ 2>/dev/null || true
	@cp $(STONE_PROVER_DIR)/e2e_test/CairoZero/$(PROGRAM)_private_input.json $(WORK_DIR)/$(PROGRAM)/ 2>/dev/null || true
	@cp $(STONE_PROVER_DIR)/e2e_test/CairoZero/$(PROGRAM)_trace.bin $(WORK_DIR)/$(PROGRAM)/ 2>/dev/null || true
	@cp $(STONE_PROVER_DIR)/e2e_test/CairoZero/$(PROGRAM)_memory.bin $(WORK_DIR)/$(PROGRAM)/ 2>/dev/null || true
	@echo "Files copied!"

# Quick test (skip Cairo run if files exist)
quick-test:
	@if [ -z "$(PROGRAM)" ]; then echo "Error: PROGRAM not set"; exit 1; fi
	@if [ ! -f "$(WORK_DIR)/$(PROGRAM)/$(PROGRAM)_proof.json" ]; then \
		echo "Proof not found, running full pipeline..."; \
		make all PROGRAM=$(PROGRAM); \
	else \
		echo "Using existing proof, preparing for EVM..."; \
		make prepare PROGRAM=$(PROGRAM); \
		make test-gas; \
	fi

# Run benchmarks
benchmark:
	@echo "Running benchmarks..."
	@./scripts/benchmark.sh 10 100 1000 10000 100000 1000000

# Deployment targets
deploy-sepolia:
	@echo "Deploying to Sepolia testnet..."
	@if [ ! -f .env.deploy ]; then \
		echo "Error: .env.deploy not found. Copy .env.deploy.example and fill in your values."; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$SEPOLIA_RPC_URL \
		--broadcast \
		-vvvv
	@echo ""
	@echo "Deployment complete! To verify contracts on Etherscan, run:"
	@echo "  make verify-contracts-sepolia"

# Deploy with automatic Etherscan verification
deploy-sepolia-verified:
	@echo "Deploying to Sepolia with verification..."
	@if [ ! -f .env.deploy ]; then \
		echo "Error: .env.deploy not found. Copy .env.deploy.example and fill in your values."; \
		exit 1; \
	fi
	@if [ -z "$$ETHERSCAN_API_KEY" ]; then \
		set -a && source .env.deploy && set +a; \
		if [ -z "$$ETHERSCAN_API_KEY" ]; then \
			echo "Error: ETHERSCAN_API_KEY not set in .env.deploy"; \
			exit 1; \
		fi; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$SEPOLIA_RPC_URL \
		--broadcast \
		--verify \
		--etherscan-api-key $$ETHERSCAN_API_KEY \
		-vvvv

deploy-sepolia-dry:
	@echo "Dry run deployment to Sepolia..."
	@if [ ! -f .env.deploy ]; then \
		echo "Error: .env.deploy not found. Copy .env.deploy.example and fill in your values."; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$SEPOLIA_RPC_URL \
		-vvvv

verify-contracts-sepolia:
	@echo "Verifying all deployed contracts on Etherscan..."
	@if [ ! -f .env.deploy ]; then \
		echo "Error: .env.deploy not found."; \
		exit 1; \
	fi
	@if [ ! -f deployment-addresses.json ]; then \
		echo "Error: deployment-addresses.json not found. Deploy first."; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && \
	VERIFIER=$$(cat deployment-addresses.json | jq -r '.verifier') && \
	echo "Verifying CpuVerifier at $$VERIFIER..." && \
	forge verify-contract $$VERIFIER \
		src/layout_starknet/CpuVerifier.sol:CpuVerifier \
		--chain sepolia \
		--etherscan-api-key $$ETHERSCAN_API_KEY \
		--watch

verify-single-sepolia:
	@echo "Verifying single contract on Sepolia..."
	@if [ -z "$(CONTRACT)" ]; then \
		echo "Error: CONTRACT address not set. Use: make verify-single-sepolia CONTRACT=0x..."; \
		exit 1; \
	fi
	@source .env.deploy && forge verify-contract $(CONTRACT) \
		src/layout_starknet/CpuVerifier.sol:CpuVerifier \
		--chain sepolia \
		--etherscan-api-key $$ETHERSCAN_API_KEY

# Verify proof on deployed contract
verify-proof-sepolia:
	@echo "Verifying proof on deployed Sepolia contract..."
	@if [ \! -f .env.deploy ]; then \
		echo "Error: .env.deploy not found."; \
		exit 1; \
	fi
	@if [ \! -f deployment-addresses.json ]; then \
		echo "Error: deployment-addresses.json not found. Deploy first with: make deploy-sepolia"; \
		exit 1; \
	fi
	@if [ \! -f input.json ]; then \
		echo "Error: input.json not found. Generate proof first with: make prepare PROGRAM=fibonacci"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/VerifyProof.s.sol:VerifyProofScript \
		--rpc-url $$SEPOLIA_RPC_URL \
		--broadcast \
		-vvvv

# View proof on-chain (read-only, no gas cost)
view-proof-sepolia:
	@echo "Viewing proof verification result (read-only)..."
	@if [ \! -f deployment-addresses.json ]; then \
		echo "Error: deployment-addresses.json not found."; \
		exit 1; \
	fi
	@VERIFIER=$$(cat deployment-addresses.json | jq -r ".verifier") && \
	set -a && source .env.deploy && set +a && \
	forge script script/VerifyProof.s.sol:VerifyProofScript \
		--rpc-url $$SEPOLIA_RPC_URL \
		-vvv

# ======================================
# Base Network Deployment Targets
# ======================================

# Deploy to Base Sepolia (testnet)
deploy-base-sepolia:
	@echo "Deploying to Base Sepolia testnet..."
	@if [ ! -f .env.deploy ]; then \
		echo "Error: .env.deploy not found. Copy .env.deploy.example and fill in your values."; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$BASE_SEPOLIA_RPC_URL \
		--broadcast \
		-vvvv
	@echo ""
	@echo "Deployment complete! To verify contracts on Basescan, run:"
	@echo "  make verify-contracts-base-sepolia"

# Deploy to Base Sepolia with automatic verification
deploy-base-sepolia-verified:
	@echo "Deploying to Base Sepolia with verification..."
	@if [ ! -f .env.deploy ]; then \
		echo "Error: .env.deploy not found. Copy .env.deploy.example and fill in your values."; \
		exit 1; \
	fi
	@if [ -z "$$BASESCAN_API_KEY" ]; then \
		set -a && source .env.deploy && set +a; \
		if [ -z "$$BASESCAN_API_KEY" ]; then \
			echo "Error: BASESCAN_API_KEY not set in .env.deploy"; \
			exit 1; \
		fi; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$BASE_SEPOLIA_RPC_URL \
		--broadcast \
		--verify \
		--verifier-url https://api-sepolia.basescan.org/api \
		--etherscan-api-key $$BASESCAN_API_KEY \
		-vvvv

# Dry run deployment to Base Sepolia
deploy-base-sepolia-dry:
	@echo "Dry run deployment to Base Sepolia..."
	@if [ ! -f .env.deploy ]; then \
		echo "Error: .env.deploy not found. Copy .env.deploy.example and fill in your values."; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$BASE_SEPOLIA_RPC_URL \
		-vvvv

# Verify contracts on Base Sepolia
verify-contracts-base-sepolia:
	@echo "Verifying all deployed contracts on Basescan..."
	@if [ ! -f .env.deploy ]; then \
		echo "Error: .env.deploy not found."; \
		exit 1; \
	fi
	@if [ ! -f deployment-addresses.json ]; then \
		echo "Error: deployment-addresses.json not found. Deploy first."; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && \
	VERIFIER=$$(cat deployment-addresses.json | jq -r '.verifier') && \
	echo "Verifying CpuVerifier at $$VERIFIER..." && \
	forge verify-contract $$VERIFIER \
		src/layout_starknet/CpuVerifier.sol:CpuVerifier \
		--chain-id 84532 \
		--verifier-url https://api-sepolia.basescan.org/api \
		--etherscan-api-key $$BASESCAN_API_KEY \
		--watch

# Verify proof on deployed Base Sepolia contract
verify-proof-base-sepolia:
	@echo "Verifying proof on deployed Base Sepolia contract..."
	@if [ \! -f .env.deploy ]; then \
		echo "Error: .env.deploy not found."; \
		exit 1; \
	fi
	@if [ \! -f deployment-addresses.json ]; then \
		echo "Error: deployment-addresses.json not found. Deploy first with: make deploy-base-sepolia"; \
		exit 1; \
	fi
	@if [ \! -f input.json ]; then \
		echo "Error: input.json not found. Generate proof first with: make prepare PROGRAM=fibonacci"; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/VerifyProof.s.sol:VerifyProofScript \
		--rpc-url $$BASE_SEPOLIA_RPC_URL \
		--broadcast \
		-vvvv

# Deploy to Base Mainnet
deploy-base:
	@echo "Deploying to Base Mainnet..."
	@echo "WARNING: This will deploy to MAINNET. Make sure you have enough ETH!"
	@read -p "Are you sure you want to deploy to mainnet? [y/N] " -n 1 -r; \
	echo; \
	if [[ ! $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "Deployment cancelled."; \
		exit 1; \
	fi
	@if [ ! -f .env.deploy ]; then \
		echo "Error: .env.deploy not found. Copy .env.deploy.example and fill in your values."; \
		exit 1; \
	fi
	@set -a && source .env.deploy && set +a && forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $$BASE_RPC_URL \
		--broadcast \
		-vvvv
	@echo ""
	@echo "Mainnet deployment complete!"
