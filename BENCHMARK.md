# Benchmarking Guide

Automated benchmarking for STARK proof verification costs.

## Quick Start

```bash
# Run default benchmarks (fibonacci_claim_index: 10 to 1000000)
make benchmark

# Or custom values
./scripts/benchmark.sh 100 500 1000 5000
```

## What It Measures

For each test case:
- **n_steps** - Execution trace length
- **FRI Steps** - Polynomial folding configuration
- **Last Layer Bound** - Final FRI layer degree
- **Proof Size** - Size in bytes
- **Public Input Size** - Input size in bytes
- **Gas Used** - Verification gas cost
- **Cost (USD)** - Dollar cost at current prices

## Configuration

Edit `scripts/benchmark.sh`:
```bash
ETH_PRICE_USD=3300  # ETH price in USD
GWEI_PRICE=0.6      # Gas price in gwei
```

## Results

Results are saved to `benchmark.md` with table format:

```
| Fibonacci Index | n_steps | FRI Steps     | Last Layer | Proof Size | Gas Used  | Cost USD |
|-----------------|---------|---------------|------------|------------|-----------|----------|
| 10              | 8192    | [0,4,4,3]     | 64         | 2156      | 3642569   | $0.007   |
| 100             | 16384   | [0,4,4,4]     | 64         | 2284      | 3685421   | $0.007   |
...
```

## Usage

### Default Test Cases

```bash
make benchmark
```

Tests: 10, 100, 1000, 10000, 100000, 1000000

### Custom Values

```bash
./scripts/benchmark.sh 50 500 5000 50000
```

### Single Test

```bash
./scripts/benchmark.sh 10000
```

## How It Works

For each fibonacci_claim_index value:

1. **Update input** - Modifies `fibonacci_input.json`
2. **Cairo run** - Generates execution trace
3. **Calculate FRI** - Optimizes FRI parameters
4. **Generate proof** - Creates STARK proof
5. **Prepare EVM** - Converts to Solidity format
6. **Run tests** - Measures gas consumption
7. **Extract stats** - Parses results
8. **Calculate cost** - Converts to USD

## Cost Calculation

```
Cost (USD) = gas_used × gwei_price × 10^-9 × eth_price
```

Example:
- Gas: 3,642,569
- Gwei: 0.6
- ETH: $3,300
- Cost: 3,642,569 × 0.6 × 10^-9 × 3300 = **$0.0072**

## Understanding Results

### Proof Size vs Gas

Larger proofs generally use more gas, but FRI configuration matters more.

### FRI Steps Impact

```
[0,4,4,4,4]    - 5 layers, larger proof, less gas per layer
[0,4,4,4,3]    - 5 layers, optimized last layer
[0,4,4,4,4,2]  - 6 layers, more verification steps
```

### n_steps Growth

As fibonacci_claim_index grows:
- n_steps increases (more computation)
- Proof size grows logarithmically
- Gas costs increase linearly

## Troubleshooting

**Benchmark fails:**
Check `bc` is installed:
```bash
sudo dnf install bc  # Fedora
```

**Cairo run fails:**
Ensure venv is configured in `.env`

**Gas extraction fails:**
Check forge test output format hasn't changed

## Tips

- Run benchmarks after optimizing FRI parameters
- Compare results before/after changes
- Use for cost estimation in production
- Track gas costs over time
