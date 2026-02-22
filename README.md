# Mini DEX — Educational Uniswap V2 Clone

A minimal, readable Uniswap V2-style DEX for learning. Deploys to Base Sepolia.

**Not production-ready.** No audits, no admin keys, no WETH support.

## Architecture

```
Factory  ─── CREATE2 ──▶  Pair (ERC20 LP token)
                              ▲
Router ──────────────────────┘
(stateless helper)
```

- **Factory**: deploys and tracks all Pair contracts
- **Pair**: holds two tokens, IS the LP token (inherits ERC20), enforces x*y=k
- **Router**: stateless — computes amounts, enforces slippage/deadline, routes calls

## Local Development

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node 18+ (optional, for scripts)

### Install

```bash
git clone <this-repo>
cd dex
forge install
```

### Run Tests

```bash
forge test -v
```

### Build

```bash
forge build
```

## Deploying to Base Sepolia

### 1. Get Base Sepolia ETH

Faucet: https://www.coinbase.com/faucets/base-ethereum-goerli-faucet

### 2. Configure environment

```bash
cp .env.example .env
# Edit .env and set:
#   PRIVATE_KEY=0x...
#   BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
#   BASESCAN_API_KEY=...  (from https://basescan.org)
source .env
```

### 3. Deploy

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url base_sepolia \
  --broadcast \
  --verify \
  -vvvv
```

Copy the logged addresses — you'll need them for interactions.

## Testing Manually with `cast`

Replace `<ROUTER>`, `<FACTORY>`, `<TOKEN_A>`, `<TOKEN_B>` with deployed addresses.

### Approve tokens to Router

```bash
cast send <TOKEN_A> "approve(address,uint256)" <ROUTER> 1000000000000000000000000 \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY

cast send <TOKEN_B> "approve(address,uint256)" <ROUTER> 1000000000000000000000000 \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

### Add Liquidity

```bash
cast send <ROUTER> \
  "addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)" \
  <TOKEN_A> <TOKEN_B> \
  10000000000000000000000 10000000000000000000000 \
  0 0 \
  <YOUR_ADDRESS> 9999999999 \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

### Swap (Token A → Token B)

```bash
cast send <ROUTER> \
  "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)" \
  1000000000000000000000 \
  900000000000000000000 \
  "[<TOKEN_A>,<TOKEN_B>]" \
  <YOUR_ADDRESS> 9999999999 \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

### Check reserves

```bash
cast call <PAIR_ADDRESS> "getReserves()(uint112,uint112)" \
  --rpc-url $BASE_SEPOLIA_RPC_URL
```

## Verifying the k Invariant

After any swap:

```bash
# Read reserves before
cast call <PAIR> "getReserves()(uint112,uint112)" --rpc-url $BASE_SEPOLIA_RPC_URL
# (r0_before, r1_before) -> k_before = r0 * r1

# Execute swap...

# Read reserves after
cast call <PAIR> "getReserves()(uint112,uint112)" --rpc-url $BASE_SEPOLIA_RPC_URL
# (r0_after, r1_after) -> k_after = r0 * r1

# k_after >= k_before  ✓  (fee is retained in reserves, so k grows slightly)
```

The invariant test in `test/DEX.t.sol::testKInvariantAfterSwap` automates this check.

## Key Math

| Formula | Purpose |
|---|---|
| `x * y = k` | Constant product invariant |
| `amountOut = (amountIn*997*reserveOut) / (reserveIn*1000 + amountIn*997)` | Swap with 0.3% fee |
| `liquidity = sqrt(amount0 * amount1) - 1000` | First mint LP tokens |
| `liquidity = min(amount0/reserve0, amount1/reserve1) * totalSupply` | Subsequent mints |
