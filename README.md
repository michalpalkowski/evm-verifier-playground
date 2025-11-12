# Ethereum STARK Verifier

Generate and verify STARK proofs on Ethereum.

## Quick Start

```bash
# Setup
make setup

# Run workflow (recommended)
make copy-cairo-files PROGRAM=fibonacci
make all-skip-cairo PROGRAM=fibonacci
```

## Requirements

- Stone prover binaries (`cpu_air_prover`, `cpu_air_verifier`)
- `stark_evm_adapter` in PATH
- Rust & Foundry
- `bc` (for benchmarks): `sudo dnf install bc`

## Usage

### Simple Workflow (No Cairo Run)

```bash
make copy-cairo-files PROGRAM=fibonacci   # Copy files from stone-prover
make prove-only PROGRAM=fibonacci         # Generate proof (auto-calculates FRI)
make prepare PROGRAM=fibonacci            # Prepare for EVM
make test-gas                             # Test on-chain
```

Or one command:
```bash
make all-skip-cairo PROGRAM=fibonacci
```

### Full Workflow (With Cairo Run)

```bash
make all PROGRAM=fibonacci
```

## Commands

```bash
make help                              # Show all commands
make setup                             # Initial setup
make clean                             # Clean generated files

# Cairo (optional)
make cairo-run PROGRAM=<name>          # Run Cairo
make copy-cairo-files PROGRAM=<name>   # Copy from stone-prover

# Proof generation
make prove-only PROGRAM=<name>         # Generate proof (auto FRI)
make verify PROGRAM=<name>             # Verify proof
make prepare PROGRAM=<name>            # Prepare for EVM

# Testing
make test                              # Run tests
make test-gas                          # With gas report

# Workflows
make all PROGRAM=<name>                # Full pipeline
make all-skip-cairo PROGRAM=<name>     # Skip cairo-run

# Utilities
make calc-fri-steps PROGRAM=<name>     # Calculate FRI steps
make benchmark                         # Run benchmark tests

# Deployment (Sepolia testnet)
make deploy-sepolia-dry                # Simulate deployment
make deploy-sepolia                    # Deploy to Sepolia
make verify-proof-sepolia              # Verify proof on-chain
```

## Configuration

Edit `.env`:
```bash
CAIRO_RUN=./scripts/cairo-run-wrapper.sh
STONE_PROVER_DIR=/path/to/stone-prover
CPU_AIR_PROVER=./programs/cpu_air_prover
CPU_AIR_VERIFIER=./programs/cpu_air_verifier
PROVER_PARAMS=./prover_settings/cpu_air_params.json
WORK_DIR=./work
```

## FRI Steps Calculator

Automatically calculates optimal FRI step sizes based on `n_steps` from public input.

Runs automatically before proof generation:
```bash
make prove-only PROGRAM=fibonacci  # Auto-calculates FRI
```

Manual:
```bash
make calc-fri-steps PROGRAM=fibonacci
```

Formula:
```
fri_degree = log2(n_steps / degree_bound) + 4
fri_step_list = [0, 4, 4, 4, ..., remainder]
```

## Project Structure

```
Ethereum_verifier/
├── examples/           # Cairo programs
├── programs/           # cpu_air_prover, cpu_air_verifier
├── prover_settings/    # cpu_air_params.json
├── scripts/            # calculate_fri_steps, prepare_input
├── src/                # Solidity verifier
├── test/               # Solidity tests
├── work/               # Generated files (gitignored)
├── .env                # Configuration
├── Makefile           # Commands
└── README.md          # This file
```

## Adding Programs

```bash
mkdir -p examples/myprogram
cp myprogram_compiled.json examples/myprogram/
cp myprogram_input.json examples/myprogram/
make all-skip-cairo PROGRAM=myprogram
```

## Deployment

Deploy to Sepolia testnet:

```bash
# Setup
cp .env.deploy.example .env.deploy
# Edit .env.deploy with your keys

# Deploy
make deploy-sepolia

# Verify proof on-chain
make prepare PROGRAM=fibonacci
make verify-proof-sepolia
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for full guide.

## Troubleshooting

**Cairo not found:** Skip cairo-run with `make all-skip-cairo`

**Missing files:** Run `make copy-cairo-files PROGRAM=<name>`

**Permission denied:** Run `chmod +x programs/* scripts/*.sh`

**Build errors:** Run `cargo build --release --workspace`

## License

Apache-2.0
