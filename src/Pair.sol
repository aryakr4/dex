// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Liquidity pool for two ERC20 tokens. The Pair contract IS the LP token (inherits ERC20).
///
/// Math overview:
///   Constant product formula: x * y = k
///   Swap fee: 0.3% taken from input (charged as amountIn * 997 / 1000)
///   Invariant check: balance0Adjusted * balance1Adjusted >= reserve0 * reserve1 * 1_000_000
///   (The 1_000_000 = 1000^2 factor accounts for the fee denominator in integer math)
contract Pair is ERC20 {
    /// @dev Minimum LP tokens burned on first mint to prevent zero-price manipulation.
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    address public token0;
    address public token1;

    /// @dev Reserves stored as uint112 to match Uniswap V2 storage layout.
    uint112 private reserve0;
    uint112 private reserve1;

    /// @dev Simple reentrancy lock — no OZ dependency needed.
    bool private _locked;

    modifier nonReentrant() {
        require(!_locked, "Pair: REENTRANT");
        _locked = true;
        _;
        _locked = false;
    }

    constructor() ERC20("Mini DEX LP", "MDEX-LP") {}

    /// @notice Called once by Factory immediately after CREATE2 deployment.
    function initialize(address _token0, address _token1) external {
        require(token0 == address(0), "Pair: ALREADY_INITIALIZED");
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }

    // ─── Internal helpers ────────────────────────────────────────────────────

    function _update(uint256 balance0, uint256 balance1) private {
        require(
            balance0 <= type(uint112).max && balance1 <= type(uint112).max,
            "Pair: OVERFLOW"
        );
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
    }

    /// @dev Babylonian integer square root.
    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    // ─── Core functions ───────────────────────────────────────────────────────

    /// @notice Deposit tokens and receive LP tokens.
    /// @dev Caller must transfer token0 and token1 to this contract BEFORE calling mint.
    ///      This is the pattern used by Router: transferFrom user → pair, then call pair.mint.
    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1) = getReserves();

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        // Amount deposited = current balance minus what was already accounted for
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            // First mint: geometric mean of deposited amounts
            // MINIMUM_LIQUIDITY (1000) is burned to address(1) permanently
            // This prevents the LP price from being manipulated to zero
            liquidity = _sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(1), MINIMUM_LIQUIDITY);
        } else {
            // Subsequent mints: proportional to existing supply (take the minimum
            // to prevent an LP from depositing in bad ratio and stealing value)
            liquidity = _min(
                (amount0 * _totalSupply) / _reserve0,
                (amount1 * _totalSupply) / _reserve1
            );
        }

        require(liquidity > 0, "Pair: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);
        _update(balance0, balance1);
    }

    /// @notice Burn LP tokens and receive underlying tokens back.
    /// @dev Caller must transfer LP tokens to this contract BEFORE calling burn.
    function burn(address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this)); // LP tokens sent to this contract

        uint256 _totalSupply = totalSupply();

        // Pro-rata share of pool
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;

        require(amount0 > 0 && amount1 > 0, "Pair: INSUFFICIENT_LIQUIDITY_BURNED");

        // Checks-effects-interactions: burn LP tokens before external calls
        _burn(address(this), liquidity);

        IERC20(token0).transfer(to, amount0);
        IERC20(token1).transfer(to, amount1);

        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this))
        );
    }

    /// @notice Exchange tokens. Caller specifies how much of each token they want out.
    ///         One of amount0Out/amount1Out must be zero.
    /// @dev Caller must transfer the input token to this contract BEFORE calling swap.
    ///      The invariant is enforced: (balance0 - fee) * (balance1 - fee) >= reserve0 * reserve1.
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external nonReentrant {
        require(amount0Out > 0 || amount1Out > 0, "Pair: INSUFFICIENT_OUTPUT_AMOUNT");

        (uint112 _reserve0, uint112 _reserve1) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "Pair: INSUFFICIENT_LIQUIDITY");

        // Send tokens out first (safe because of nonReentrant guard)
        if (amount0Out > 0) IERC20(token0).transfer(to, amount0Out);
        if (amount1Out > 0) IERC20(token1).transfer(to, amount1Out);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        // Compute how much of each token came IN (balance increase over expected-after-output)
        uint256 amount0In = balance0 > (_reserve0 - amount0Out)
            ? balance0 - (_reserve0 - amount0Out)
            : 0;
        uint256 amount1In = balance1 > (_reserve1 - amount1Out)
            ? balance1 - (_reserve1 - amount1Out)
            : 0;

        require(amount0In > 0 || amount1In > 0, "Pair: INSUFFICIENT_INPUT_AMOUNT");

        // Invariant check with fee:
        //   adjusted balance = balance * 1000 - amountIn * 3
        //   (subtracting 0.3% fee from the input side)
        //   Require: adjusted0 * adjusted1 >= reserve0 * reserve1 * 1_000_000
        uint256 balance0Adjusted = balance0 * 1000 - amount0In * 3;
        uint256 balance1Adjusted = balance1 * 1000 - amount1In * 3;

        require(
            balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * uint256(_reserve1) * 1_000_000,
            "Pair: K_INVARIANT_VIOLATED"
        );

        _update(balance0, balance1);
    }
}
