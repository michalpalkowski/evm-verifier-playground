# Deployment Guide

Deploy STARK Verifier to Sepolia testnet.

## Quick Start

```bash
# 1. Setup deployment config
cp .env.deploy.example .env.deploy
# Edit .env.deploy with your keys

# 2. Deploy
make deploy-sepolia

# 3. Verify a proof
make prepare PROGRAM=fibonacci
make verify-proof-sepolia
```

## Prerequisites

### 1. Get Sepolia ETH

Faucets:
- [Alchemy Sepolia Faucet](https://sepoliafaucet.com/)
- [Infura Sepolia Faucet](https://www.infura.io/faucet/sepolia)
- [Chainlink Faucet](https://faucets.chain.link/sepolia)

### 2. Get RPC URL

- **Alchemy**: https://www.alchemy.com/ (recommended)
- **Infura**: https://www.infura.io/
- **Public**: https://rpc.sepolia.org

### 3. Get Etherscan API Key

1. https://etherscan.io/
2. My Profile → API Keys → Add

## Configuration

```bash
cp .env.deploy.example .env.deploy
```

Edit `.env.deploy`:

### Required

```bash
PRIVATE_KEY=your_private_key_without_0x
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY
```

### Optional (only for Etherscan verification)

```bash
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY  # Optional!
```

**⚠️ NEVER commit `.env.deploy`**

## Deployment

### Dry Run

```bash
make deploy-sepolia-dry
```

### Deploy (No Verification)

```bash
make deploy-sepolia
```

Deploys all contracts without Etherscan verification:
1. 9 periodic columns
2. MemoryPageFactRegistry
3. CpuOods
4. CpuConstraintPoly
5. CpuVerifier

Takes ~5-10 minutes.
Addresses saved to `deployment-addresses.json`

**No Etherscan API key needed!**

### Deploy with Verification

```bash
make deploy-sepolia-verified
```

Same as above but automatically verifies on Etherscan.
Requires `ETHERSCAN_API_KEY` in `.env.deploy`

### Verify After Deployment

If you deployed without verification:

```bash
make verify-contracts-sepolia
```

Verifies all deployed contracts on Etherscan.

## Verify Proof On-Chain

### Generate Proof

```bash
make all-skip-cairo PROGRAM=fibonacci
```

### Verify on Sepolia

```bash
make verify-proof-sepolia
```

This sends transaction to deployed verifier.

### View Only (No Gas)

```bash
make view-proof-sepolia
```

Read-only call, no transaction.

## Cost Estimation

At 1 gwei:

| Action | Gas | Cost |
|--------|-----|------|
| Deploy all | ~20M | 0.02 ETH |
| Verify proof | ~3.6M | 0.0036 ETH |

## Troubleshooting

**"insufficient funds"** - Get more Sepolia ETH

**"deployment-addresses.json not found"** - Run `make deploy-sepolia` first

**"input.json not found"** - Run `make prepare PROGRAM=fibonacci` first

**Verification failed** - Check proof is valid locally with `make test`

## Using Deployed Contract

```solidity
ICpuVerifier verifier = ICpuVerifier(0xYourAddress);
verifier.verifyProofExternal(proofParams, proof, publicInput);
```

## Mainnet

**⚠️ Costs real ETH!**

1. Update `foundry.toml` with mainnet RPC
2. Update `.env.deploy` with mainnet URL
3. Deploy: `forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify`

## Security

- Use hardware wallet for mainnet
- Test on testnet first
- Audit contracts
- Keep keys secure
