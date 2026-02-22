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
}
