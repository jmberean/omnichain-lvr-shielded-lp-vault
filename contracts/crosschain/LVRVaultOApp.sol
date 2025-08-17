// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// -----------------------------------------------------------------------------
/// Temporary compile-safe stub for the optional LayerZero v2 OApp piece.
/// - Keeps the same outward shape you'd call from scripts (setPeer, broadcast)
/// - Avoids inheritance/constructor wiring issues while we finish core Hook/Vault.
///
/// When you're ready to use the real OApp, replace this file with the real
/// OApp-based implementation and deploy with proper endpoint + owner params.
/// -----------------------------------------------------------------------------
contract LVRVaultOApp {
    address public immutable endpoint;
    address public immutable owner;

    constructor(address endpoint_, address owner_) {
        endpoint = endpoint_;
        owner = owner_;
    }

    /// @notice Set the peer on another chain (stubbed; no-op for compile)
    function setPeer(uint32 /*eid*/, bytes32 /*peer*/) external {
        // no-op in stub
    }

    /// @notice Broadcast a payload cross-chain (stubbed; no-op for compile)
    function broadcast(bytes32 /*topic*/, bytes calldata /*data*/, uint32 /*dstEid*/, bytes calldata /*options*/)
        external
        payable
    {
        // no-op in stub
    }
}
