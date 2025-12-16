# Ethereum STARK Verifier

Solidity contracts for verifying STARK proofs on Ethereum.

## 🚀 Quick Start

### Prerequisites

- Foundry (`forge`, `cast`)
- Rust
- direnv (for environment variables)

### Setup

1. **Install direnv:**

2. **Configure environment:**
   ```bash
   # Copy example file
   cp .env.example .env
   
   # Edit .env and fill in required values:
   # - PRIVATE_KEY=your_private_key_here (required)
   # - SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY (required)
   # 
   # Optional (defaults to examples/factorial-bootloader/):
   # - ANNOTATED_PROOF=examples/factorial-bootloader/annotated_proof.json
   # - INPUT_JSON=examples/factorial-bootloader/input.json
   # - FACT_TOPOLOGIES=bootloader/fact_topologies.json
   ```

3. **Allow direnv:**
   ```bash
   direnv allow .
   ```

### Deploy Contracts

```bash
# Deploy to Sepolia testnet
cargo run --bin deploy sepolia

# Dry run (simulate without broadcasting)
cargo run --bin deploy sepolia --dry

# Deploy to Base Sepolia
cargo run --bin deploy base-sepolia
```

### Test Programs

```bash
# Test a program example (fibonacci or factorial)
cargo run --bin test example factorial
cargo run --bin test example fibonacci

# Test bootloader version
cargo run --bin test example factorial --bootloader

# Run all Forge tests
cargo run --bin test all

# Run all tests with gas report
cargo run --bin test all --gas
```

### Verify Proofs

Verify large bootloader proofs using the split approach:

```bash
# With network selection (uses env vars for RPC URL)
cargo run --bin verify sepolia
cargo run --bin verify base-sepolia

# Or with explicit paths
cargo run --bin verify sepolia -- \
  --annotated-proof work/bootloader/annotated_proof.json \
  --input-json work/bootloader/input.json \
  --fact-topologies bootloader/fact_topologies.json
```

The verification process:
1. **Splits the proof** into smaller parts (trace decommitments, FRI decommitments, continuous pages)
2. **Registers each part** separately to avoid gas/calldata limits
3. **Verifies the main proof** using `input.json` directly

## 📋 Requirements

- Pre-generated `input.json` files (from `prepare-proof` repository)
- `deployment-addresses.json` with deployed contract addresses (after deployment)

## 📚 Examples

Example `input.json` files are stored in `examples/` directory:

- `examples/fibonacci/input.json` - Fibonacci program proof
- `examples/factorial/input.json` - Factorial program proof
- `examples/fibonacci-bootloader/input.json` - Fibonacci via bootloader
- `examples/factorial-bootloader/input.json` - Factorial via bootloader

## ⚠️ Important Notes

- **This is not a production version** - a production implementation can be found on Ethereum mainnet
- **Compatibility:** Only supports proofs generated with `layout=starknet`
- **Proof generation:** This repository only handles verification - proof generation must be done separately using `prepare-proof` repository
- Proofs must use `keccak256` for EVM compatibility

## License

Apache-2.0
