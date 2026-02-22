// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Pair is ERC20 {
    address public token0;
    address public token1;

    constructor() ERC20("Mini DEX LP", "MDEX-LP") {}

    function initialize(address _token0, address _token1) external {
        require(token0 == address(0), "Pair: ALREADY_INITIALIZED");
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() public view returns (uint112, uint112) {
        return (0, 0); // stub
    }

    function mint(address) external returns (uint256) { return 0; }  // stub
    function burn(address) external returns (uint256, uint256) { return (0, 0); } // stub
    function swap(uint256, uint256, address) external {} // stub
}
