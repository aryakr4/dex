// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/mocks/MockERC20.sol";
import "../src/Factory.sol";
import "../src/Pair.sol";

contract DEXTest is Test {
    MockERC20 tokenA;
    MockERC20 tokenB;

    address alice = makeAddr("alice");

    function setUp() public {
        tokenA = new MockERC20("Token Alpha", "ALPHA", 18);
        tokenB = new MockERC20("Token Beta", "BETA", 18);
    }

    function testMockERC20Mint() public {
        tokenA.mint(alice, 1000e18);
        assertEq(tokenA.balanceOf(alice), 1000e18);
        assertEq(tokenA.decimals(), 18);
        assertEq(tokenA.symbol(), "ALPHA");
    }

    function testCreatePair() public {
        Factory factory = new Factory();
        address pair = factory.createPair(address(tokenA), address(tokenB));
        assertNotEq(pair, address(0), "Pair not created");
        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        // Sorted order must also work
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair);
    }

    function testCreatePairDuplicateReverts() public {
        Factory factory = new Factory();
        factory.createPair(address(tokenA), address(tokenB));
        vm.expectRevert("Factory: PAIR_EXISTS");
        factory.createPair(address(tokenA), address(tokenB));
    }

    function testCreatePairIdenticalReverts() public {
        Factory factory = new Factory();
        vm.expectRevert("Factory: IDENTICAL_ADDRESSES");
        factory.createPair(address(tokenA), address(tokenA));
    }

    function testPairMintFirstLiquidity() public {
        Factory f = new Factory();
        address pair = f.createPair(address(tokenA), address(tokenB));

        // Transfer tokens directly to pair (simulating what Router does)
        tokenA.mint(address(pair), 100e18);
        tokenB.mint(address(pair), 100e18);

        uint256 lp = Pair(pair).mint(alice);

        assertGt(lp, 0, "No LP tokens minted");
        assertEq(Pair(pair).balanceOf(alice), lp);

        (uint112 r0, uint112 r1) = Pair(pair).getReserves();
        assertEq(r0, 100e18);
        assertEq(r1, 100e18);
    }

    function testPairBurn() public {
        Factory f = new Factory();
        address pair = f.createPair(address(tokenA), address(tokenB));

        tokenA.mint(address(pair), 100e18);
        tokenB.mint(address(pair), 100e18);
        uint256 lp = Pair(pair).mint(alice);

        // Transfer LP tokens to pair for burning
        vm.prank(alice);
        Pair(pair).transfer(address(pair), lp);

        (uint256 a0, uint256 a1) = Pair(pair).burn(alice);

        assertGt(a0, 0);
        assertGt(a1, 0);
        assertEq(Pair(pair).balanceOf(alice), 0);
    }

    function testPairSwap() public {
        Factory f = new Factory();
        address pair = f.createPair(address(tokenA), address(tokenB));

        // Add 100k of each token as liquidity
        tokenA.mint(address(pair), 100_000e18);
        tokenB.mint(address(pair), 100_000e18);
        Pair(pair).mint(alice);

        // Determine which reserve belongs to tokenA (the input token)
        bool tokenAIsToken0 = Pair(pair).token0() == address(tokenA);
        (uint112 r0, uint112 r1) = Pair(pair).getReserves();
        (uint256 reserveIn, uint256 reserveOut) = tokenAIsToken0
            ? (uint256(r0), uint256(r1))
            : (uint256(r1), uint256(r0));

        uint256 amountIn = 1000e18;
        uint256 amountInWithFee = amountIn * 997;
        uint256 expected = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);

        // Send tokenA to pair, get tokenB out
        tokenA.mint(address(pair), amountIn);

        uint256 balBefore = tokenB.balanceOf(alice);
        // Route output to the correct slot based on actual token ordering
        (uint256 amount0Out, uint256 amount1Out) = tokenAIsToken0
            ? (uint256(0), expected)
            : (expected, uint256(0));
        Pair(pair).swap(amount0Out, amount1Out, alice);

        assertEq(tokenB.balanceOf(alice) - balBefore, expected);
    }
}
