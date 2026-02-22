# Mini DEX — Claude Code Context

## Project Overview

Educational Uniswap V2-style DEX (Factory + Pair + Router) targeting Base Sepolia.
**Not production-ready** — no audits, no admin keys, no WETH support.

## Tech Stack

- Solidity ^0.8.20
- Foundry 1.5.x (forge binary at `~/.foundry/bin/forge`)
- OpenZeppelin v5.2.0 (ERC20 base only, in `lib/openzeppelin-contracts`)
- forge-std v1.15.0 (in `lib/forge-std`)

## Essential Commands

```bash
~/.foundry/bin/forge test             # run all 14 tests
~/.foundry/bin/forge test -v          # verbose output
~/.foundry/bin/forge build            # compile
~/.foundry/bin/forge snapshot         # regenerate .gas-snapshot
```

Always use the full path `~/.foundry/bin/forge` — forge is not on PATH by default.

## Source Layout

```
src/
  Factory.sol       — CREATE2 pair deployment, sorted token registry
  Pair.sol          — LP token + AMM core (mint/burn/swap, k-invariant)
  Router.sol        — stateless helper: slippage, deadline, multi-hop
  mocks/
    MockERC20.sol   — open-mint ERC20 for testnet use
script/
  Deploy.s.sol      — deploys Factory + Router + 2 mock tokens to Base Sepolia
test/
  DEX.t.sol         — single test file, 14 tests covering all contracts
```

## Architecture

```
Factory ── CREATE2 ──▶ Pair (IS the LP token, inherits ERC20)
                          ▲
Router ───────────────────┘  (stateless, no storage)
```

- Factory sorts tokens by address (token0 < token1) for canonical storage keys
- Pair stores reserves as uint112; uses Babylonian sqrt for first mint
- Router's `_swap` routes output of each hop directly to the next pair (or final recipient)
- 0.3% fee: `amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)`

## Key Design Decisions

- **Token ordering**: Factory always sorts token0 < token1. Tests must detect actual ordering via `Pair.token0()` rather than assuming which token comes first — do NOT hardcode `swap(0, amount, to)` without checking.
- **Minimum liquidity**: 1000 LP tokens are permanently burned to `address(1)` on first mint to prevent zero-price manipulation.
- **No SafeERC20**: Intentional — mirrors Uniswap V2 style. ERC20 transfer return values are not checked.
- **Reentrancy**: Simple boolean lock in Pair, no OZ ReentrancyGuard dependency.

## Test File

All tests live in `test/DEX.t.sol` in one contract `DEXTest`. setUp() deploys factory, router, tokenA, tokenB, tokenC and mints `1_000_000e18` of each to alice with full router approval.

Groups: MockERC20 · Factory · Pair (direct) · Router integration · Invariant · Multi-hop

## Repository

- **GitHub**: https://github.com/aryakr4/dex
- **Remote**: `origin` → `https://github.com/aryakr4/dex.git`
- **Branch**: `master`
- **Git email**: aryakrish4@gmail.com

```bash
git push origin master   # push latest commits
```

## Deployment

Requires `.env` with `PRIVATE_KEY`, `BASE_SEPOLIA_RPC_URL`, `BASESCAN_API_KEY`.

```bash
PRIVATE_KEY=<key> ~/.foundry/bin/forge script script/Deploy.s.sol:Deploy -vvvv   # dry-run
# add --rpc-url base_sepolia --broadcast --verify for live deploy
```
