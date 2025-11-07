#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
else
    echo -e "${RED}Error: .env file not found. Run 'make setup' first.${NC}"
    exit 1
fi

# Function to print colored messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if program name is provided
if [ -z "$1" ]; then
    error "Usage: $0 <program_name> [skip_cairo_run]"
fi

PROGRAM=$1
SKIP_CAIRO_RUN=${2:-false}

# Create work directory
PROGRAM_DIR="$PROJECT_ROOT/$WORK_DIR/$PROGRAM"
mkdir -p "$PROGRAM_DIR"

info "Starting proof generation for: $PROGRAM"
info "Working directory: $PROGRAM_DIR"

# Step 1: Run Cairo program (optional)
if [ "$SKIP_CAIRO_RUN" = "false" ]; then
    if [ ! -f "$PROJECT_ROOT/examples/$PROGRAM/${PROGRAM}_compiled.json" ]; then
        error "Program file not found: examples/$PROGRAM/${PROGRAM}_compiled.json"
    fi

    info "Step 1/5: Running Cairo program..."
    cd "$PROJECT_ROOT"
    $CAIRO_RUN \
        --program="examples/$PROGRAM/${PROGRAM}_compiled.json" \
        --layout=starknet \
        --program_input="examples/$PROGRAM/${PROGRAM}_input.json" \
        --air_public_input="$PROGRAM_DIR/${PROGRAM}_public_input.json" \
        --air_private_input="$PROGRAM_DIR/${PROGRAM}_private_input.json" \
        --trace_file="$PROGRAM_DIR/${PROGRAM}_trace.bin" \
        --memory_file="$PROGRAM_DIR/${PROGRAM}_memory.bin" \
        --print_output \
        --proof_mode
    info "Cairo run completed ✓"
else
    warn "Skipping Cairo run (using existing files)"
fi

# Step 2: Generate STARK proof
info "Step 2/5: Generating STARK proof..."
cd "$PROJECT_ROOT"
$CPU_AIR_PROVER \
    --out_file="$PROGRAM_DIR/${PROGRAM}_proof.json" \
    --private_input_file="$PROGRAM_DIR/${PROGRAM}_private_input.json" \
    --public_input_file="$PROGRAM_DIR/${PROGRAM}_public_input.json" \
    --prover_config_file="$PROVER_CONFIG" \
    --parameter_file="$PROVER_PARAMS" \
    --generate_annotations true
info "STARK proof generated ✓"

# Step 3: Verify proof
info "Step 3/5: Verifying STARK proof..."
$CPU_AIR_VERIFIER \
    --in_file="$PROGRAM_DIR/${PROGRAM}_proof.json" \
    --extra_output_file="$PROGRAM_DIR/${PROGRAM}_extra_output.json" \
    --annotation_file="$PROGRAM_DIR/${PROGRAM}_annotation_file.json"
info "Proof verification completed ✓"

# Step 4: Generate annotated proof for EVM
info "Step 4/5: Generating annotated proof for EVM..."
$STARK_EVM_ADAPTER gen-annotated-proof \
    --stone-proof-file "$PROGRAM_DIR/${PROGRAM}_proof.json" \
    --stone-annotation-file "$PROGRAM_DIR/${PROGRAM}_annotation_file.json" \
    --stone-extra-annotation-file "$PROGRAM_DIR/${PROGRAM}_extra_output.json" \
    --output "$PROGRAM_DIR/annotated_proof.json"
info "Annotated proof generated ✓"

# Step 5: Prepare input for Solidity verifier
info "Step 5/5: Preparing input for Solidity verifier..."
cargo run --package prepare-input --bin prepare-input \
    "$PROGRAM_DIR/annotated_proof.json" \
    "$PROGRAM_DIR/input.json"
info "EVM input prepared ✓"

# Create symlinks in root directory for convenience
cd "$PROJECT_ROOT"
ln -sf "$PROGRAM_DIR/annotated_proof.json" annotated_proof.json
ln -sf "$PROGRAM_DIR/input.json" input.json

info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "✓ Proof generation completed successfully!"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Output files:"
echo "  • STARK Proof:      $PROGRAM_DIR/${PROGRAM}_proof.json"
echo "  • Annotated Proof:  $PROGRAM_DIR/annotated_proof.json"
echo "  • EVM Input:        $PROGRAM_DIR/input.json"
echo ""
echo "Next steps:"
echo "  • Run tests:        forge test --gas-report"
echo "  • Or use Makefile:  make test-gas"
