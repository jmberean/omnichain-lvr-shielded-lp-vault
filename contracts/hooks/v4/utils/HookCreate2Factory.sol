// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal CREATE2 factory for deploying the Hook at a permission-encoded address.
contract HookCreate2Factory {
    event Deployed(address addr, bytes32 salt);

    /// @dev Deploys `bytecode` via CREATE2 with `salt`.
    function deploy(bytes memory bytecode, bytes32 salt) external returns (address addr) {
        require(bytecode.length != 0, "BYTECODE_EMPTY");
        assembly {
            let code := add(bytecode, 0x20)
            let size := mload(bytecode)
            addr := create2(0, code, size, salt)
        }
        require(addr != address(0), "CREATE2_FAILED");
        emit Deployed(addr, salt);
    }

    /// @dev Computes the CREATE2 address this factory would use for `salt` & `initCodeHash`.
    function compute(bytes32 salt, bytes32 initCodeHash) external view returns (address) {
        return address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff), address(this), salt, initCodeHash
        )))));
    }
}
