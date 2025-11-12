# Deployment Quick Start

## 1. Get Sepolia ETH

https://sepoliafaucet.com/

## 2. Setup Config

```bash
cp .env.deploy.example .env.deploy
nano .env.deploy
```

Fill in (ETHERSCAN_API_KEY optional):
```bash
PRIVATE_KEY=your_key_without_0x
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
```

## 3. Dry Run

```bash
make deploy-sepolia-dry
```

## 4. Deploy

```bash
make deploy-sepolia
```

Wait 5-10 minutes. Addresses saved to `deployment-addresses.json`.

*Optional: Verify on Etherscan*
```bash
make verify-contracts-sepolia  # Needs ETHERSCAN_API_KEY
```

## 5. Verify Proof

```bash
# Generate proof first
make all-skip-cairo PROGRAM=fibonacci

# Verify on-chain
make verify-proof-sepolia
```

Done! 🎉

---

**Cost:** ~0.02 ETH Sepolia (~$0 real money)

**Time:** ~10 minutes total

**Full guide:** [DEPLOYMENT.md](DEPLOYMENT.md)
