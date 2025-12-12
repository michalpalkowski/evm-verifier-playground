# Ethereum STARK Verifier

## ⚠️ Project Status

**This is not a production version of an EVM verifier - a production implementation can be found on the Ethereum mainnet**

Generate and verify STARK proofs on Ethereum.

## 🚀 Quick Start - Run Examples

Choose one of the examples:

### 1️⃣ Fibonacci Example

```bash
make setup                                    # First time setup
make copy-cairo-files PROGRAM=fibonacci       # Copy files
make all-skip-cairo PROGRAM=fibonacci         # Generate proof and test
```

### 2️⃣ Factorial Example

```bash
make setup                                    # First time setup
make copy-cairo-files PROGRAM=factorial       # Copy files
make all-skip-cairo PROGRAM=factorial         # Generate proof and test
```

### 3️⃣ Bootloader Example

```bash
make setup                                    # First time setup
make create-pie PROGRAM=factorial              # Create PIE from Cairo program
make bootloader-all PROGRAM=factorial         # Run bootloader and generate proof
```

---

## ✅ Already Have Proofs?

If you already have generated proofs, you can verify and test them (IMPORTANT: proof must be generated in layout starknet and with keccak256):

### Regular Programs (Fibonacci, Factorial, etc.)

```bash
make verify PROGRAM=fibonacci           # Generate annotations with cpu_air_verifier
make prepare PROGRAM=fibonacci          # Prepare for EVM (includes verify step)
make test-gas                           # Real EVM verification using Solidity verifier
```

**Note:** 
- `make verify` uses `cpu_air_verifier` to generate additional annotations needed for EVM preparation (not actual EVM verification)
- `make prepare` converts the proof to EVM format (requires verify step)
- `make test-gas` performs the actual on-chain verification using the Solidity verifier contract

### Bootloader Programs

```bash
make bootloader-verify PROGRAM=factorial    # Generate annotations with cpu_air_verifier
make bootloader-prepare PROGRAM=factorial  # Prepare for EVM (includes verify step)
make test-gas                               # Real EVM verification using Solidity verifier
```

**Note:** Proofs should be in `work/<PROGRAM>/<PROGRAM>_proof.json` (or `work/bootloader/<PROGRAM>_proof.json` for bootloader).

---

## 📋 Requirements

- Stone prover binaries in programs/ (`cpu_air_prover`, `cpu_air_verifier`)
- `stark_evm_adapter` in PATH - converts Stone prover proofs to EVM format (used in `make prepare`)
- Rust & Foundry

## 📚 More Commands

### Proof Generation
```bash
make copy-cairo-files PROGRAM=<name>   # Copy files from stone-prover
make prove-only PROGRAM=<name>         # Generate proof (auto FRI)
make verify PROGRAM=<name>             # Verify proof
make prepare PROGRAM=<name>            # Prepare for EVM
make all-skip-cairo PROGRAM=<name>     # Full pipeline (skip cairo-run)
make all PROGRAM=<name>                # Full pipeline (with cairo-run)
```

### Bootloader
```bash
make create-pie PROGRAM=<name>         # Create PIE from program
make bootloader-cairo-run PROGRAM=<name> # Run bootloader with PIE
make bootloader-prove PROGRAM=<name>   # Generate bootloader proof
make bootloader-verify PROGRAM=<name>  # Verify bootloader proof
make bootloader-prepare PROGRAM=<name> # Prepare for EVM
make bootloader-all PROGRAM=<name>     # Full bootloader pipeline
```

### Testing
```bash
make test                              # Run tests
make test-gas                          # Tests with gas report
make benchmark                         # Benchmarks
```

### Deployment (Sepolia testnet)
```bash
make deploy-sepolia-dry                # Simulate deployment
make deploy-sepolia                    # Deploy to Sepolia
make verify-proof-sepolia              # Verify proof on-chain
```

## Configuration

Edit `.env`:
```bash
CAIRO_RUN=./scripts/cairo-run-wrapper.sh
STONE_PROVER_DIR=/path/to/stone-prover
CAIRO_LANG_DIR=/path/to/cairo-lang-latest  # For bootloader
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

## Troubleshooting

**Missing files:** Run `make copy-cairo-files PROGRAM=<name>`

**Permission denied:** Run `chmod +x programs/* scripts/*.sh`

## License

Apache-2.0
