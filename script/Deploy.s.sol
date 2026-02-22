// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Factory.sol";
import "../src/Router.sol";
import "../src/mocks/MockERC20.sol";

/// @notice Deploys the full DEX to Base Sepolia.
///         Set PRIVATE_KEY and BASE_SEPOLIA_RPC_URL in .env before running.
///
/// Run with:
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url base_sepolia \
///     --broadcast \
///     --verify \
///     -vvvv
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // Deploy two mock ERC20 tokens for testing
        MockERC20 tokenA = new MockERC20("Token Alpha", "ALPHA", 18);
        MockERC20 tokenB = new MockERC20("Token Beta", "BETA", 18);

        // Mint 1,000,000 of each to the deployer
        tokenA.mint(deployer, 1_000_000e18);
        tokenB.mint(deployer, 1_000_000e18);

        // Deploy DEX core
        Factory factory = new Factory();
        Router router = new Router(address(factory));

        vm.stopBroadcast();

        // Log all addresses for use with `cast` or a frontend
        console.log("=== Mini DEX Deployed to Base Sepolia ===");
        console.log("Deployer  :", deployer);
        console.log("TokenA    :", address(tokenA));
        console.log("TokenB    :", address(tokenB));
        console.log("Factory   :", address(factory));
        console.log("Router    :", address(router));
    }
}
