.PHONY: help setup clean prove verify test all

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
