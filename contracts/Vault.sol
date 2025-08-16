// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVault} from "./interfaces/IVault.sol";

/// @title LVR-Shielded LP Vault (Telemetry + Apply Mode)
/// @notice Minimal, gas-conscious vault that trusts a designated Hook for applyMode,
///         and allows an offchain keeper to record actions for telemetry.
/// @dev This contract is intentionally simple: no funds custody; it is a
///      coordination/telemetry surface for the demo + subgraph.
contract Vault is IVault {
    address public override admin;
    address public override hook;
    address public override keeper;

    struct HomePlacement {
        int24 centerTick;
        int24 halfWidthTicks;
    }

    mapping(bytes32 => HomePlacement) private _home; // poolId => placement

    modifier onlyAdmin() {
        require(msg.sender == admin, "VAULT:NOT_ADMIN");
        _;
    }

    modifier onlyHook() {
        require(msg.sender == hook, "VAULT:NOT_HOOK");
        _;
    }

    modifier onlyKeeper() {
        require(msg.sender == keeper, "VAULT:NOT_KEEPER");
        _;
    }

    constructor(address admin_) {
        require(admin_ != address(0), "VAULT:BAD_ADMIN");
        admin = admin_;
    }

    /// @notice Admin handoff.
    function setAdmin(address admin_) external onlyAdmin {
        require(admin_ != address(0), "VAULT:BAD_ADMIN");
        admin = admin_;
    }

    function setHook(address hook_) external override onlyAdmin {
        require(hook_ != address(0), "VAULT:BAD_HOOK");
        hook = hook_;
    }

    function setKeeper(address keeper_) external override onlyAdmin {
        require(keeper_ != address(0), "VAULT:BAD_KEEPER");
        keeper = keeper_;
    }

    function getHome(bytes32 poolId) external view override returns (int24 centerTick, int24 halfWidthTicks) {
        HomePlacement memory h = _home[poolId];
        return (h.centerTick, h.halfWidthTicks);
    }

    /// @inheritdoc IVault
    function applyMode(
        bytes32 poolId,
        Mode mode_,
        uint64 epoch,
        string calldata reason,
        int24 optCenterTick,
        int24 optHalfWidthTicks
    ) external override onlyHook {
        // If hints provided, record as home placement for visibility.
        if (optCenterTick != int24(0) || optHalfWidthTicks != int24(0)) {
            _home[poolId] = HomePlacement({centerTick: optCenterTick, halfWidthTicks: optHalfWidthTicks});
        }

        emit ModeApplied(
            poolId,
            uint8(mode_),
            epoch,
            reason,
            optCenterTick,
            optHalfWidthTicks
        );
    }

    /// @inheritdoc IVault
    function keeperRebalance(
        bytes32 poolId,
        int24 centerTick,
        int24 halfWidthTicks,
        string calldata reason,
        uint8 mode_,
        uint64 epoch
    ) external override onlyKeeper {
        // Keeper snapshot (also refresh home if provided)
        if (centerTick != int24(0) || halfWidthTicks != int24(0)) {
            _home[poolId] = HomePlacement({centerTick: centerTick, halfWidthTicks: halfWidthTicks});
        }
        emit LiquidityAction(poolId, mode_, centerTick, halfWidthTicks, epoch, reason);
    }
}
