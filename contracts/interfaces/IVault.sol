// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IVault for LVR-Shielded LP Vault
/// @notice Vault receives "applyMode" calls from the Hook (onlyHook)
///         and records keeper actions for telemetry.
interface IVault {
    enum Mode {
        NORMAL,    // 0
        WIDENED,   // 1
        RISK_OFF   // 2
    }

    event ModeApplied(
        bytes32 indexed poolId,
        uint8 mode,
        uint64 epoch,
        string reason,
        int24 centerTick,
        int24 halfWidthTicks
    );

    event LiquidityAction(
        bytes32 indexed poolId,
        uint8 mode,
        int24 centerTick,
        int24 halfWidthTicks,
        uint64 epoch,
        string action
    );

    function admin() external view returns (address);
    function hook() external view returns (address);
    function keeper() external view returns (address);

    function setHook(address hook_) external;
    function setKeeper(address keeper_) external;

    function getHome(bytes32 poolId) external view returns (int24 centerTick, int24 halfWidthTicks);

    function applyMode(
        bytes32 poolId,
        Mode mode_,
        uint64 epoch,
        string calldata reason,
        int24 optCenterTick,
        int24 optHalfWidthTicks
    ) external;

    function keeperRebalance(
        bytes32 poolId,
        int24 centerTick,
        int24 halfWidthTicks,
        string calldata reason,
        uint8 mode_,
        uint64 epoch
    ) external;
}
