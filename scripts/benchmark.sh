#!/bin/bash
set -e

# Benchmark script for STARK proof verification
# Tests different fibonacci_claim_index values and measures gas costs

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
PROGRAM="fibonacci"
BENCHMARK_FILE="benchmark.md"
ETH_PRICE_USD=3300
GWEI_PRICE=0.6

# Test cases
TEST_CASES=(
    10
    100
    1000
    10000
    100000
    1000000
)

# Allow custom test cases from command line
if [ $# -gt 0 ]; then
    TEST_CASES=("$@")
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}         STARK Proof Verification Benchmark${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "Testing fibonacci_claim_index values: ${TEST_CASES[@]}"
echo "ETH Price: \$${ETH_PRICE_USD}, Gas Price: ${GWEI_PRICE} gwei"
echo ""

# Initialize benchmark file
cat > "$BENCHMARK_FILE" << 'EOF'
# STARK Proof Verification Benchmark

EOF

echo "Date: $(date '+%Y-%m-%d %H:%M:%S')" >> "$BENCHMARK_FILE"
echo "" >> "$BENCHMARK_FILE"
echo "## Configuration" >> "$BENCHMARK_FILE"
echo "" >> "$BENCHMARK_FILE"
echo "- **ETH Price:** \$${ETH_PRICE_USD}" >> "$BENCHMARK_FILE"
echo "- **Gas Price:** ${GWEI_PRICE} gwei" >> "$BENCHMARK_FILE"
echo "" >> "$BENCHMARK_FILE"
echo "## Results" >> "$BENCHMARK_FILE"
echo "" >> "$BENCHMARK_FILE"
echo "| Fibonacci Index | n_steps | FRI Steps | Last Layer Bound | Proof Size (bytes) | Public Input | Gas Used | Cost (USD) |" >> "$BENCHMARK_FILE"
echo "|-----------------|---------|-----------|------------------|--------------------|--------------|---------:|------------|" >> "$BENCHMARK_FILE"

# Backup original input
cp examples/fibonacci/fibonacci_input.json examples/fibonacci/fibonacci_input.json.bak

# Run benchmarks
for index in "${TEST_CASES[@]}"; do
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Testing fibonacci_claim_index = $index${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Update input file
    echo "{" > examples/fibonacci/fibonacci_input.json
    echo "    \"fibonacci_claim_index\": $index" >> examples/fibonacci/fibonacci_input.json
    echo "}" >> examples/fibonacci/fibonacci_input.json

    # Run full workflow
    echo -e "${YELLOW}Step 1/5: Running Cairo...${NC}"
    make cairo-run PROGRAM=fibonacci > /dev/null 2>&1 || {
        echo "Cairo run failed for index $index"
        continue
    }

    echo -e "${YELLOW}Step 2/5: Calculating FRI steps...${NC}"
    make calc-fri-steps PROGRAM=fibonacci > /dev/null 2>&1

    echo -e "${YELLOW}Step 3/5: Generating proof...${NC}"
    make prove-only PROGRAM=fibonacci > /dev/null 2>&1 || {
        echo "Proof generation failed for index $index"
        continue
    }

    echo -e "${YELLOW}Step 4/5: Preparing for EVM...${NC}"
    make prepare PROGRAM=fibonacci > /dev/null 2>&1 || {
        echo "EVM preparation failed for index $index"
        continue
    }

    echo -e "${YELLOW}Step 5/5: Running tests...${NC}"
    TEST_OUTPUT=$(make test-gas 2>&1)

    # Extract data
    N_STEPS=$(cat work/fibonacci/fibonacci_public_input.json | jq -r '.n_steps')
    FRI_STEPS=$(cat prover_settings/cpu_air_params.json | jq -r '.stark.fri.fri_step_list | map(tostring) | join(",")')
    FRI_STEPS_DISPLAY="[${FRI_STEPS}]"
    LAST_LAYER=$(cat prover_settings/cpu_air_params.json | jq -r '.stark.fri.last_layer_degree_bound')

    # Extract proof sizes from test output
    PROOF_LENGTH=$(echo "$TEST_OUTPUT" | grep -A 1 "Proof length:" | tail -1 | tr -d ' ')
    PUBLIC_INPUT_LENGTH=$(echo "$TEST_OUTPUT" | grep -A 1 "Public input length:" | tail -1 | tr -d ' ')

    # Extract gas used (from table format: | name | min | avg | median | max | calls |)
    GAS_USED=$(echo "$TEST_OUTPUT" | grep "verifyProofExternal" | awk -F'|' '{print $3}' | tr -d ' ' | head -1)

    if [ -z "$GAS_USED" ]; then
        echo "Could not extract gas usage for index $index"
        continue
    fi

    # Calculate cost in USD
    # Cost = gas * gwei_price * 1e-9 * eth_price
    COST_USD=$(echo "scale=6; $GAS_USED * $GWEI_PRICE * 0.000000001 * $ETH_PRICE_USD" | bc)

    echo ""
    echo "Results:"
    echo "  n_steps:          $N_STEPS"
    echo "  FRI steps:        $FRI_STEPS_DISPLAY"
    echo "  Last layer bound: $LAST_LAYER"
    echo "  Proof size:       $PROOF_LENGTH bytes"
    echo "  Public input:     $PUBLIC_INPUT_LENGTH bytes"
    echo "  Gas used:         $GAS_USED"
    echo "  Cost:             \$${COST_USD}"
    echo ""

    # Append to benchmark file
    printf "| %-15s | %-7s | %-9s | %-16s | %-18s | %-12s | %8s | \$%-9s |\n" \
        "$index" "$N_STEPS" "$FRI_STEPS_DISPLAY" "$LAST_LAYER" "$PROOF_LENGTH" \
        "$PUBLIC_INPUT_LENGTH" "$GAS_USED" "$COST_USD" >> "$BENCHMARK_FILE"
done

# Restore original input
mv examples/fibonacci/fibonacci_input.json.bak examples/fibonacci/fibonacci_input.json

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Benchmark complete! Results saved to: $BENCHMARK_FILE${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "View results:"
echo "  cat $BENCHMARK_FILE"
