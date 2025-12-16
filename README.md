# Ethereum STARK Verifier

## 🔍 Verifying Proofs

### Quick Verification

Verify large bootloader proofs using the split approach:

```bash
# Simple usage (with direnv configured)
cargo run --bin verify

# Or with explicit paths
cargo run --bin verify -- \
  --annotated-proof work/bootloader/annotated_proof.json \
  --input-json work/bootloader/input.json \
  --fact-topologies bootloader/fact_topologies.json

# Or use Makefile (uses default paths)
make verify-proof-sepolia-split
```

The verification process:
1. **Splits the proof** into smaller parts (trace decommitments, FRI decommitments, continuous pages)
2. **Registers each part** separately to avoid gas/calldata limits
3. **Verifies the main proof** using `input.json` directly

### Environment Setup

This project uses `direnv` to automatically load environment variables from `.env`.

**First-time setup:**

1. **Install direnv:**

2. **Set up environment variables:**
   ```bash
   # Copy example file
   cp .env.example .env
   
   # Edit .env with your values:
   # - SEPOLIA_RPC_URL (your Ethereum RPC endpoint)
   # - PRIVATE_KEY (your wallet private key)
   # - ANNOTATED_PROOF (optional, defaults to work/bootloader/annotated_proof.json)
   # - INPUT_JSON (optional, defaults to work/bootloader/input.json)
   # - FACT_TOPOLOGIES (optional, defaults to bootloader/fact_topologies.json)
   ```

After setup, `direnv` will automatically load variables from `.env` whenever you `cd` into the project directory.

**Required files:**
- `.env` file with `PRIVATE_KEY` and `SEPOLIA_RPC_URL`
- `deployment-addresses.json` with deployed contract addresses
- Proof files (`annotated_proof.json`, `input.json`, `fact_topologies.json`)

---

to test gps(general purpose verifier) flow you need to create input.json (prepared proof from full-bootloader) in main folder, you can do this with prepared examples like fibonnaci or factorial with command  e.g ```make test-program-bootloader PROGRAM=factorial ``` this will create input.json which you can verify. 

To test CPU verifier you need to overwrite input.json with proof without bootloader, you can do that with prepared proof by running e.g ``` make test-program PROGRAM=fibonacci``` you can test it with ``forge test`` command (CpuVerifier.t.sol).

## ⚠️ Project Status

**This is not a production version of an EVM verifier - a production implementation can be found on the Ethereum mainnet**

Solidity contracts for verifying STARK proofs on Ethereum.

**⚠️ Important:** The EVM verifier is currently compatible only with proofs generated using `layout=starknet`. Proofs generated with other layouts (e.g., `recursive_with_poseidon`) are not supported yet.

## 🚀 Quick Start

### Prerequisites

- Foundry (for testing and deployment)
- Rust (for building dependencies)

### Setup

```bash
make setup                    # Install dependencies
```

### Testing with Pre-generated Proofs

This repository only handles **verification** of STARK proofs. You need pre-generated `input.json` files to test.

```bash
# Test verification with existing input.json
make test-program PROGRAM=fibonacci
```

### Available Test Commands

```bash
make test                     # Run all tests
make test-gas                 # Run tests with gas report
make test-program PROGRAM=fibonacci    # Test specific program
make test-program-bootloader PROGRAM=factorial  # Test bootloader proof
```

## 📋 Requirements

- Foundry (`forge`, `cast`)
- Pre-generated `input.json` files (from `prepare-proof` repository)

## 📚 Examples

Example `input.json` files are stored in `examples/` directory:

- `examples/fibonacci/input.json` - Fibonacci program proof
- `examples/factorial/input.json` - Factorial program proof
- `examples/fibonacci-bootloader/input.json` - Fibonacci via bootloader
- `examples/factorial-bootloader/input.json` - Factorial via bootloader

## 🌐 Deployment

### Sepolia Testnet

```bash
# Setup
cp .env.example .env
# Edit .env with your keys

# Deploy
make deploy-sepolia

# Verify proof on-chain
make verify-proof-sepolia
```

### Base Network

```bash
make deploy-base-sepolia      # Deploy to Base Sepolia
make deploy-base              # Deploy to Base Mainnet (⚠️ CAUTION)
```

## 📁 Project Structure

```
ethereum_verifier/
├── src/                      # Solidity verifier contracts
├── test/                     # Foundry tests
├── script/                   # Deployment scripts
├── examples/                 # Pre-generated input.json files
└── lib/                      # Dependencies (forge-std, evm-verifier-columns)
```

## 🔍 Verification Process

1. **Obtain input.json** - You need a pre-generated `input.json` file from a proof generation tool

2. **Place input.json** in the examples directory:
   ```bash
   cp /path/to/input.json examples/fibonacci/input.json
   ```

3. **Test Verification**:
   ```bash
   make test-program PROGRAM=fibonacci
   ```

4. **Deploy and Verify On-chain**:
   ```bash
   make deploy-sepolia
   make verify-proof-sepolia
   ```

## 📝 Notes

- This repository **only handles verification** - proof generation must be done separately
- **Compatibility:** The EVM verifier currently supports only proofs generated with `layout=starknet`
- Proofs must use `keccak256` for EVM compatibility
- The verifier contracts are in `src/layout_starknet/`

## Troubleshooting

**Missing input.json:** Obtain a pre-generated `input.json` file from your proof generation tool

**Test failures:** Ensure `input.json` is in the correct location (`examples/PROGRAM/input.json`)

**Deployment issues:** Check `.env` configuration

## License

Apache-2.0
