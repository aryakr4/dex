// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Pair.sol";

/// @notice Deploys and tracks all Pair contracts using CREATE2 for deterministic addresses.
contract Factory {
    /// @dev token0 < token1 always (sorted). Use getPair(A,B) == getPair(B,A).
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 index);

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /// @notice Deploy a new Pair for tokenA/tokenB. Reverts if pair already exists.
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "Factory: IDENTICAL_ADDRESSES");
        require(tokenA != address(0) && tokenB != address(0), "Factory: ZERO_ADDRESS");

        // Sort so storage key is canonical regardless of input order
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);

        require(getPair[token0][token1] == address(0), "Factory: PAIR_EXISTS");

        // CREATE2: deterministic address from sorted token pair
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pair = address(new Pair{salt: salt}());
        Pair(pair).initialize(token0, token1);

        // Register both orderings so callers don't need to sort
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}
