// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IVault {
    enum Mode { NORMAL, WIDENED, RISK_OFF }
    
    // Events
    event ModeApplied(
        bytes32 indexed poolId,
        uint8 oldMode,
        uint8 newMode,
        uint64 epoch,
        string reason
    );
    
    event LiquidityAction(
        bytes32 indexed poolId,
        uint8 mode,
        uint64 epoch,
        int256 baseDelta,
        int256 quoteDelta,
        string reason
    );
    
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);
    event HookChanged(address indexed oldHook, address indexed newHook);
    event KeeperChanged(address indexed oldKeeper, address indexed newKeeper);
    
    event ReentryConfigChanged(
        uint256 oldCooldownPeriod,
        uint256 oldMinLiquidityThreshold,
        uint256 oldMaxExposureBps,
        bool oldAutoReentryEnabled,
        uint256 newCooldownPeriod,
        uint256 newMinLiquidityThreshold,
        uint256 newMaxExposureBps,
        bool newAutoReentryEnabled
    );
    
    event ReentryInitiated(
        bytes32 indexed poolId,
        uint8 mode,
        uint64 timestamp
    );
    
    event Paused(address account);
    event Unpaused(address account);
    
    // View functions
    function poolId() external view returns (bytes32);
    function currentMode() external view returns (Mode);
    function modeEpoch() external view returns (uint64);
    function lastModeChange() external view returns (uint64);
    
    function admin() external view returns (address);
    function hook() external view returns (address);
    function keeper() external view returns (address);
    
    // Admin functions
    function setAdmin(address admin_) external;
    function setHook(address hook_) external;
    function setKeeper(address keeper_) external;
    function setReentryConfig(
        uint256 cooldownPeriod,
        uint256 minLiquidityThreshold,
        uint256 maxExposureBps,
        bool autoReentryEnabled
    ) external;
    function pause() external;
    function unpause() external;
    
    // Hook functions
    function applyMode(Mode mode, uint64 epoch, string calldata reason) external;
    
    // Keeper functions
    function keeperRebalance(int256 baseDelta, int256 quoteDelta, string calldata reason) external;
}