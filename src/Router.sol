// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Factory.sol";
import "./Pair.sol";

/// @notice Stateless routing contract. Computes optimal amounts, enforces slippage/deadline,
///         and orchestrates token transfers into Pair contracts.
///         No state stored here — all pool state lives in Pair contracts.
contract Router {
    address public immutable factory;

    constructor(address _factory) {
        factory = _factory;
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        _;
    }

    // ─── Math helpers ─────────────────────────────────────────────────────────

    /// @notice Compute output amount given an input and reserves.
    ///         Formula: amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
    ///         The 997/1000 factors encode the 0.3% fee without floating point.
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        require(amountIn > 0, "Router: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "Router: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    /// @notice Simulate a multi-hop swap and return output at each step.
    /// @param path Array of token addresses: [tokenIn, hop1, ..., tokenOut]
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        public
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "Router: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        for (uint256 i = 0; i < path.length - 1; i++) {
            address pair = Factory(factory).getPair(path[i], path[i + 1]);
            require(pair != address(0), "Router: PAIR_NOT_FOUND");

            (uint112 r0, uint112 r1) = Pair(pair).getReserves();
            address token0 = Pair(pair).token0();

            // Determine which reserve is "in" vs "out" for this hop
            (uint256 reserveIn, uint256 reserveOut) = path[i] == token0
                ? (uint256(r0), uint256(r1))
                : (uint256(r1), uint256(r0));

            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // ─── Liquidity helpers ────────────────────────────────────────────────────

    /// @dev Compute optimal token amounts to deposit given desired amounts and current reserves.
    ///      If the pair is new (no reserves), use full desired amounts.
    ///      Otherwise, scale one side down to maintain price ratio.
    function _computeLiquidityAmounts(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal view returns (uint256 amountA, uint256 amountB) {
        address pair = Factory(factory).getPair(tokenA, tokenB);

        if (pair == address(0)) {
            // New pair — use full desired amounts
            return (amountADesired, amountBDesired);
        }

        (uint112 r0, uint112 r1) = Pair(pair).getReserves();
        address token0 = Pair(pair).token0();
        (uint256 reserveA, uint256 reserveB) = tokenA == token0
            ? (uint256(r0), uint256(r1))
            : (uint256(r1), uint256(r0));

        if (reserveA == 0 && reserveB == 0) {
            return (amountADesired, amountBDesired);
        }

        // Try to use all of amountADesired, scale B proportionally
        uint256 amountBOptimal = (amountADesired * reserveB) / reserveA;
        if (amountBOptimal <= amountBDesired) {
            require(amountBOptimal >= amountBMin, "Router: INSUFFICIENT_B_AMOUNT");
            return (amountADesired, amountBOptimal);
        }

        // amountBDesired is the limiting factor; scale A down
        uint256 amountAOptimal = (amountBDesired * reserveA) / reserveB;
        require(amountAOptimal >= amountAMin, "Router: INSUFFICIENT_A_AMOUNT");
        return (amountAOptimal, amountBDesired);
    }

    // ─── Liquidity ────────────────────────────────────────────────────────────

    /// @notice Add liquidity to a pool. Creates the pair if it doesn't exist.
    /// @param amountADesired Max tokens to deposit for A
    /// @param amountBDesired Max tokens to deposit for B
    /// @param amountAMin Minimum A to deposit (slippage protection)
    /// @param amountBMin Minimum B to deposit (slippage protection)
    /// @param to Recipient of LP tokens
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // Create pair if it doesn't exist
        address pair = Factory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = Factory(factory).createPair(tokenA, tokenB);
        }

        (amountA, amountB) = _computeLiquidityAmounts(
            tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin
        );

        // Transfer tokens from caller to pair, then trigger mint
        IERC20(tokenA).transferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).transferFrom(msg.sender, pair, amountB);

        liquidity = Pair(pair).mint(to);
    }

    /// @notice Remove liquidity by burning LP tokens.
    /// @param liquidity LP token amount to burn
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "Router: PAIR_NOT_FOUND");

        // Transfer LP tokens from caller to pair, then trigger burn
        IERC20(pair).transferFrom(msg.sender, pair, liquidity);

        (uint256 amount0, uint256 amount1) = Pair(pair).burn(to);

        // Map amounts back to tokenA/tokenB order
        address token0 = Pair(pair).token0();
        (amountA, amountB) = tokenA == token0
            ? (amount0, amount1)
            : (amount1, amount0);

        require(amountA >= amountAMin, "Router: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "Router: INSUFFICIENT_B_AMOUNT");
    }

    // ─── Swap ─────────────────────────────────────────────────────────────────

    /// @notice Swap an exact input amount through a token path.
    /// @param amountIn Exact input token amount
    /// @param amountOutMin Minimum output (slippage protection)
    /// @param path [tokenIn, ..., tokenOut] — each adjacent pair must have a pool
    /// @param to Recipient of output tokens
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "Router: INSUFFICIENT_OUTPUT_AMOUNT");

        // Transfer input token to first pair
        address firstPair = Factory(factory).getPair(path[0], path[1]);
        IERC20(path[0]).transferFrom(msg.sender, firstPair, amounts[0]);

        _swap(amounts, path, to);
    }

    /// @dev Execute swaps along a path. For each hop, send output directly to next pair
    ///      (or to the final recipient on the last hop).
    function _swap(uint256[] memory amounts, address[] calldata path, address to) internal {
        for (uint256 i = 0; i < path.length - 1; i++) {
            address pair = Factory(factory).getPair(path[i], path[i + 1]);
            address token0 = Pair(pair).token0();

            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = path[i] == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));

            // For multi-hop: output goes to next pair. For last hop: output goes to `to`.
            address recipient = i < path.length - 2
                ? Factory(factory).getPair(path[i + 1], path[i + 2])
                : to;

            Pair(pair).swap(amount0Out, amount1Out, recipient);
        }
    }
}
