// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// You can optionally extract MockPoolManager to its own file
// if you want to reuse it across multiple test files

contract MockPoolManager {
    function unlock(bytes calldata) external pure returns (bytes memory) {
        return "";
    }
    
    function getPool(bytes32) external pure returns (bytes memory) {
        return "";
    }
    
    function initialize(PoolKey calldata, uint160, bytes calldata) external pure {
        // Mock implementation
    }
}