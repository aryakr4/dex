// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/mocks/MockERC20.sol";

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
}
