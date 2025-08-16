// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal CREATE2 factory for deterministic deployments.
contract HookCreate2Factory {
    event Deployed(address indexed addr, bytes32 indexed salt);

    function deploy(bytes32 salt, bytes memory bytecode) external returns (address addr) {
        require(bytecode.length != 0, "code=0");
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(addr != address(0), "create2 failed");
        emit Deployed(addr, salt);
    }
}
