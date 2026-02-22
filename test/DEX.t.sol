// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/Pair.sol";
import "../src/Router.sol";
import "../src/mocks/MockERC20.sol";

contract DEXTest is Test {
    Factory factory;
    Router router;
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockERC20 tokenC;

    address alice = makeAddr("alice");

    uint256 constant INITIAL = 1_000_000e18;
    uint256 constant DEADLINE = type(uint256).max;

    function setUp() public {
        factory = new Factory();
        router = new Router(address(factory));

        tokenA = new MockERC20("Token Alpha", "ALPHA", 18);
        tokenB = new MockERC20("Token Beta", "BETA", 18);
        tokenC = new MockERC20("Token Gamma", "GAMMA", 18);

        tokenA.mint(alice, INITIAL);
        tokenB.mint(alice, INITIAL);
        tokenC.mint(alice, INITIAL);

        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        tokenC.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    // ─── MockERC20 ────────────────────────────────────────────────────────────

    function testMockERC20Mint() public {
        tokenA.mint(alice, 1000e18);
        // alice already has INITIAL, so total is INITIAL + 1000e18
        assertEq(tokenA.balanceOf(alice), INITIAL + 1000e18);
        assertEq(tokenA.decimals(), 18);
        assertEq(tokenA.symbol(), "ALPHA");
    }

    // ─── Factory ──────────────────────────────────────────────────────────────

    function testCreatePair() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));
        assertNotEq(pair, address(0));
        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair);
    }

    function testCreatePairDuplicateReverts() public {
        factory.createPair(address(tokenA), address(tokenB));
        vm.expectRevert("Factory: PAIR_EXISTS");
        factory.createPair(address(tokenA), address(tokenB));
    }

    function testCreatePairIdenticalReverts() public {
        vm.expectRevert("Factory: IDENTICAL_ADDRESSES");
        factory.createPair(address(tokenA), address(tokenA));
    }

    // ─── Pair (direct) ───────────────────────────────────────────────────────

    function testPairMintFirstLiquidity() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));

        tokenA.mint(address(pair), 100e18);
        tokenB.mint(address(pair), 100e18);
        uint256 lp = Pair(pair).mint(alice);

        assertGt(lp, 0);
        assertEq(Pair(pair).balanceOf(alice), lp);

        (uint112 r0, uint112 r1) = Pair(pair).getReserves();
        assertEq(r0, 100e18);
        assertEq(r1, 100e18);
    }

    function testPairBurn() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));

        tokenA.mint(address(pair), 100e18);
        tokenB.mint(address(pair), 100e18);
        uint256 lp = Pair(pair).mint(alice);

        vm.prank(alice);
        Pair(pair).transfer(address(pair), lp);

        (uint256 a0, uint256 a1) = Pair(pair).burn(alice);

        assertGt(a0, 0);
        assertGt(a1, 0);
        assertEq(Pair(pair).balanceOf(alice), 0);
    }

    function testPairSwapDirect() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));

        tokenA.mint(address(pair), 100_000e18);
        tokenB.mint(address(pair), 100_000e18);
        Pair(pair).mint(alice);

        // Determine actual token ordering to route swap correctly
        bool tokenAIsToken0 = Pair(pair).token0() == address(tokenA);
        (uint112 r0, uint112 r1) = Pair(pair).getReserves();
        (uint256 reserveIn, uint256 reserveOut) = tokenAIsToken0
            ? (uint256(r0), uint256(r1))
            : (uint256(r1), uint256(r0));

        uint256 amountIn = 1000e18;
        uint256 amountInWithFee = amountIn * 997;
        uint256 expected = (amountInWithFee * reserveOut)
            / (reserveIn * 1000 + amountInWithFee);

        tokenA.mint(address(pair), amountIn);
        uint256 balBefore = tokenB.balanceOf(alice);

        (uint256 amount0Out, uint256 amount1Out) = tokenAIsToken0
            ? (uint256(0), expected)
            : (expected, uint256(0));
        Pair(pair).swap(amount0Out, amount1Out, alice);

        assertEq(tokenB.balanceOf(alice) - balBefore, expected);
    }

    // ─── Router integration ───────────────────────────────────────────────────

    function testAddLiquidity() public {
        vm.startPrank(alice);
        (uint256 amountA, uint256 amountB, uint256 lp) = router.addLiquidity(
            address(tokenA), address(tokenB),
            100e18, 100e18,
            0, 0,
            alice, DEADLINE
        );
        vm.stopPrank();

        assertGt(lp, 0, "No LP tokens minted");
        assertEq(amountA, 100e18);
        assertEq(amountB, 100e18);

        address pair = factory.getPair(address(tokenA), address(tokenB));
        (uint112 r0, uint112 r1) = Pair(pair).getReserves();
        assertEq(r0, 100e18);
        assertEq(r1, 100e18);
    }

    function testRemoveLiquidity() public {
        vm.startPrank(alice);
        (, , uint256 lp) = router.addLiquidity(
            address(tokenA), address(tokenB),
            100e18, 100e18,
            0, 0,
            alice, DEADLINE
        );

        address pair = factory.getPair(address(tokenA), address(tokenB));
        IERC20(pair).approve(address(router), lp);

        uint256 balABefore = tokenA.balanceOf(alice);
        uint256 balBBefore = tokenB.balanceOf(alice);

        (uint256 outA, uint256 outB) = router.removeLiquidity(
            address(tokenA), address(tokenB),
            lp,
            0, 0,
            alice, DEADLINE
        );
        vm.stopPrank();

        assertGt(outA, 0);
        assertGt(outB, 0);
        assertGt(tokenA.balanceOf(alice), balABefore);
        assertGt(tokenB.balanceOf(alice), balBBefore);
        assertEq(IERC20(pair).balanceOf(alice), 0);
    }

    function testSwapExactTokensForTokens() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA), address(tokenB),
            100_000e18, 100_000e18,
            0, 0, alice, DEADLINE
        );

        uint256 balBefore = tokenB.balanceOf(alice);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory amounts = router.swapExactTokensForTokens(
            1000e18,
            900e18, // 10% slippage tolerance
            path,
            alice,
            DEADLINE
        );
        vm.stopPrank();

        assertGe(amounts[1], 900e18, "amountOut below min");
        assertGt(tokenB.balanceOf(alice), balBefore);
    }

    function testSwapDeadlineReverts() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA), address(tokenB),
            100_000e18, 100_000e18,
            0, 0, alice, DEADLINE
        );

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.warp(1000); // jump ahead in time

        vm.expectRevert("Router: EXPIRED");
        router.swapExactTokensForTokens(
            1000e18, 0, path, alice,
            block.timestamp - 1 // expired deadline
        );
        vm.stopPrank();
    }

    function testSwapSlippageReverts() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA), address(tokenB),
            100_000e18, 100_000e18,
            0, 0, alice, DEADLINE
        );

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.expectRevert("Router: INSUFFICIENT_OUTPUT_AMOUNT");
        router.swapExactTokensForTokens(
            1000e18,
            999_999e18, // absurdly high min — will never be satisfied
            path, alice, DEADLINE
        );
        vm.stopPrank();
    }

    // ─── Invariant ────────────────────────────────────────────────────────────

    function testKInvariantAfterSwap() public {
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA), address(tokenB),
            100_000e18, 100_000e18,
            0, 0, alice, DEADLINE
        );

        address pair = factory.getPair(address(tokenA), address(tokenB));
        (uint112 r0Before, uint112 r1Before) = Pair(pair).getReserves();
        uint256 kBefore = uint256(r0Before) * uint256(r1Before);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        router.swapExactTokensForTokens(1000e18, 0, path, alice, DEADLINE);
        vm.stopPrank();

        (uint112 r0After, uint112 r1After) = Pair(pair).getReserves();
        uint256 kAfter = uint256(r0After) * uint256(r1After);

        // k must be >= before swap (it grows slightly due to fee retention in reserves)
        assertGe(kAfter, kBefore, "k invariant violated: k decreased after swap");
    }

    // ─── Multi-hop ────────────────────────────────────────────────────────────

    function testMultiHopSwap() public {
        vm.startPrank(alice);

        // Create A-B pool
        router.addLiquidity(
            address(tokenA), address(tokenB),
            100_000e18, 100_000e18,
            0, 0, alice, DEADLINE
        );

        // Create B-C pool
        router.addLiquidity(
            address(tokenB), address(tokenC),
            100_000e18, 100_000e18,
            0, 0, alice, DEADLINE
        );

        uint256 balCBefore = tokenC.balanceOf(alice);

        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        uint256[] memory amounts = router.swapExactTokensForTokens(
            1000e18,
            800e18, // ~20% slippage tolerance for 2-hop
            path,
            alice,
            DEADLINE
        );
        vm.stopPrank();

        assertGe(amounts[2], 800e18, "Multi-hop output below min");
        assertGt(tokenC.balanceOf(alice), balCBefore);
    }
}
