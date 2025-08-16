// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IVault} from "./interfaces/IVault.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Vault
 * @notice LVR-shielded LP vault with mode-based liquidity management
 * @dev Implements reentrancy protection and pausability for security
 */
contract Vault is IVault, ReentrancyGuard, Pausable {
    // Constants
    uint256 private constant MAX_BPS = 10_000;
    uint256 private constant MAX_REASON_LENGTH = 256;
    
    // State variables
    bytes32 private immutable _poolId;
    Mode private _mode;
    uint64 private _epoch;
    uint64 private _lastModeChange;
    
    address private _admin;
    address private _hook;
    address private _keeper;
    
    // Re-entry decision engine parameters
    ReentryConfig private _reentryConfig;
    
    struct ReentryConfig {
        uint256 cooldownPeriod;  // Minimum time between mode changes
        uint256 minLiquidityThreshold;  // Minimum liquidity to maintain
        uint256 maxExposureBps;  // Maximum exposure in basis points
        bool autoReentryEnabled;  // Whether automatic re-entry is enabled
    }
    
    // Modifiers
    modifier onlyAdmin() {
        require(msg.sender == _admin, "VAULT: NOT_ADMIN");
        _;
    }
    
    modifier onlyHook() {
        require(msg.sender == _hook, "VAULT: NOT_HOOK");
        _;
    }
    
    modifier onlyKeeper() {
        require(msg.sender == _keeper, "VAULT: NOT_KEEPER");
        _;
    }
    
    modifier validAddress(address addr) {
        require(addr != address(0), "VAULT: ZERO_ADDRESS");
        _;
    }
    
    modifier validReason(string calldata reason) {
        require(bytes(reason).length <= MAX_REASON_LENGTH, "VAULT: REASON_TOO_LONG");
        _;
    }
    
    /**
     * @notice Constructor
     * @param poolId_ The Uniswap v4 pool identifier
     */
    constructor(bytes32 poolId_) {
        require(poolId_ != bytes32(0), "VAULT: INVALID_POOL_ID");
        _poolId = poolId_;
        _mode = Mode.NORMAL;
        _epoch = 0;
        _admin = msg.sender;
        _lastModeChange = uint64(block.timestamp);
        
        // Initialize re-entry config with safe defaults
        _reentryConfig = ReentryConfig({
            cooldownPeriod: 300,  // 5 minutes
            minLiquidityThreshold: 1e18,  // 1 unit minimum
            maxExposureBps: 8000,  // 80% max exposure
            autoReentryEnabled: false
        });
        
        emit AdminChanged(address(0), _admin);
    }
    
    // View functions
    function poolId() external view returns (bytes32) {
        return _poolId;
    }
    
    function currentMode() external view returns (Mode) {
        return _mode;
    }
    
    function modeEpoch() external view returns (uint64) {
        return _epoch;
    }
    
    function lastModeChange() external view returns (uint64) {
        return _lastModeChange;
    }
    
    function admin() external view returns (address) {
        return _admin;
    }
    
    function hook() external view returns (address) {
        return _hook;
    }
    
    function keeper() external view returns (address) {
        return _keeper;
    }
    
    function reentryConfig() external view returns (ReentryConfig memory) {
        return _reentryConfig;
    }
    
    // Admin functions
    function setAdmin(address admin_) 
        external 
        onlyAdmin 
        validAddress(admin_) 
    {
        address oldAdmin = _admin;
        _admin = admin_;
        emit AdminChanged(oldAdmin, admin_);
    }
    
    function setHook(address hook_) 
        external 
        onlyAdmin 
        validAddress(hook_) 
    {
        address oldHook = _hook;
        _hook = hook_;
        emit HookChanged(oldHook, hook_);
    }
    
    function setKeeper(address keeper_) 
        external 
        onlyAdmin 
        validAddress(keeper_) 
    {
        address oldKeeper = _keeper;
        _keeper = keeper_;
        emit KeeperChanged(oldKeeper, keeper_);
    }
    
    /**
     * @notice Configure re-entry decision engine parameters
     * @param cooldownPeriod Minimum seconds between mode changes
     * @param minLiquidityThreshold Minimum liquidity to maintain
     * @param maxExposureBps Maximum exposure in basis points
     * @param autoReentryEnabled Whether automatic re-entry is enabled
     */
    function setReentryConfig(
        uint256 cooldownPeriod,
        uint256 minLiquidityThreshold,
        uint256 maxExposureBps,
        bool autoReentryEnabled
    ) external onlyAdmin {
        require(cooldownPeriod <= 1 hours, "VAULT: COOLDOWN_TOO_LONG");
        require(maxExposureBps <= MAX_BPS, "VAULT: INVALID_BPS");
        
        ReentryConfig memory oldConfig = _reentryConfig;
        _reentryConfig = ReentryConfig({
            cooldownPeriod: cooldownPeriod,
            minLiquidityThreshold: minLiquidityThreshold,
            maxExposureBps: maxExposureBps,
            autoReentryEnabled: autoReentryEnabled
        });
        
        emit ReentryConfigChanged(
            oldConfig.cooldownPeriod,
            oldConfig.minLiquidityThreshold,
            oldConfig.maxExposureBps,
            oldConfig.autoReentryEnabled,
            cooldownPeriod,
            minLiquidityThreshold,
            maxExposureBps,
            autoReentryEnabled
        );
    }
    
    function pause() external onlyAdmin {
        _pause();
    }
    
    function unpause() external onlyAdmin {
        _unpause();
    }
    
    // Hook functions
    /**
     * @notice Apply a new mode based on volatility signals
     * @param mode The new mode to apply
     * @param epoch The epoch number for this mode change
     * @param reason Human-readable reason for the change
     */
    function applyMode(Mode mode, uint64 epoch, string calldata reason) 
        external 
        onlyHook 
        whenNotPaused
        validReason(reason)
        nonReentrant
    {
        // Validate mode transition
        require(_canTransitionTo(mode), "VAULT: INVALID_TRANSITION");
        
        // Check cooldown period
        require(
            block.timestamp >= _lastModeChange + _reentryConfig.cooldownPeriod,
            "VAULT: COOLDOWN_ACTIVE"
        );
        
        Mode oldMode = _mode;
        _mode = mode;
        _epoch = epoch;
        _lastModeChange = uint64(block.timestamp);
        
        emit ModeApplied(_poolId, uint8(oldMode), uint8(mode), epoch, reason);
        
        // Check for automatic re-entry
        if (_reentryConfig.autoReentryEnabled && _shouldReenter(mode)) {
            _initiateReentry(mode);
        }
    }
    
    // Keeper functions
    /**
     * @notice Execute a liquidity rebalance
     * @param baseDelta Change in base token liquidity
     * @param quoteDelta Change in quote token liquidity
     * @param reason Human-readable reason for the rebalance
     */
    function keeperRebalance(
        int256 baseDelta, 
        int256 quoteDelta, 
        string calldata reason
    ) 
        external 
        onlyKeeper 
        whenNotPaused
        validReason(reason)
        nonReentrant
    {
        // Validate deltas are within reasonable bounds
        require(
            _validateDeltas(baseDelta, quoteDelta),
            "VAULT: INVALID_DELTAS"
        );
        
        emit LiquidityAction(
            _poolId, 
            uint8(_mode), 
            _epoch, 
            baseDelta, 
            quoteDelta, 
            reason
        );
    }
    
    // Internal functions
    function _canTransitionTo(Mode newMode) private view returns (bool) {
        // Define valid state transitions
        if (_mode == Mode.NORMAL) {
            return newMode == Mode.WIDENED || newMode == Mode.RISK_OFF;
        } else if (_mode == Mode.WIDENED) {
            return newMode == Mode.NORMAL || newMode == Mode.RISK_OFF;
        } else if (_mode == Mode.RISK_OFF) {
            // Can only return to WIDENED first, then NORMAL
            return newMode == Mode.WIDENED;
        }
        return false;
    }
    
    function _shouldReenter(Mode mode) private view returns (bool) {
        // Re-entry decision logic
        if (mode == Mode.NORMAL) {
            return false; // Already in normal mode
        }
        
        // Additional checks would include:
        // - Current liquidity levels
        // - Market conditions
        // - Time since last change
        // For now, return false as placeholder
        return false;
    }
    
    function _initiateReentry(Mode mode) private {
        emit ReentryInitiated(_poolId, uint8(mode), uint64(block.timestamp));
        // Additional re-entry logic would go here
    }
    
    function _validateDeltas(int256 baseDelta, int256 quoteDelta) private pure returns (bool) {
        // Ensure at least one delta is non-zero
        if (baseDelta == 0 && quoteDelta == 0) {
            return false;
        }
        
        // Check for reasonable bounds (example: max 100M tokens)
        int256 maxDelta = 100_000_000 * 1e18;
        if (baseDelta > maxDelta || baseDelta < -maxDelta) {
            return false;
        }
        if (quoteDelta > maxDelta || quoteDelta < -maxDelta) {
            return false;
        }
        
        return true;
    }
}