// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/hooks/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IPriceOracle} from "../oracle/IPriceOracle.sol";
import {PriceMath} from "../libraries/PriceMath.sol";

/**
 * @title LVRGuardV4Hook
 * @notice Uniswap v4 hook for LVR protection through volatility monitoring
 * @dev Implements afterSwap hook to detect price volatility and trigger vault mode changes
 */
contract LVRGuardV4Hook is BaseHook {
    using PriceMath for uint256;
    using PoolIdLibrary for PoolKey;
    
    // Constants
    uint256 private constant MAX_BPS = 10_000;
    uint256 private constant MIN_STALE_AFTER = 30;  // 30 seconds minimum
    uint256 private constant MAX_STALE_AFTER = 1 hours;
    
    // Immutables
    IVault public immutable VAULT;
    IPriceOracle public immutable ORACLE;
    address public immutable ADMIN;
    
    // State variables (packed for gas efficiency)
    struct PriceState {
        uint128 lastPriceE18;  // Packed: 128 bits for price (sufficient for most tokens)
        uint64 lastUpdateTime;  // Packed: 64 bits for timestamp
        bool initialized;       // Packed: 8 bits
    }
    
    mapping(bytes32 => PriceState) public priceStates;
    
    struct Config {
        uint128 widenBps;      // Threshold for WIDENED mode
        uint128 riskOffBps;    // Threshold for RISK_OFF mode
        uint64 staleAfter;     // Seconds before price is considered stale
    }
    
    Config public config;
    
    // Events
    event Signal(
        bytes32 indexed poolId,
        uint256 priceE18,
        uint64 updatedAt,
        uint256 volatilityBps
    );
    
    event ConfigUpdated(
        uint256 oldWidenBps,
        uint256 oldRiskOffBps,
        uint64 oldStaleAfter,
        uint256 newWidenBps,
        uint256 newRiskOffBps,
        uint64 newStaleAfter
    );
    
    event OracleError(bytes32 indexed poolId, string reason);
    
    // Errors
    error InvalidAdmin();
    error InvalidVault();
    error InvalidOracle();
    error InvalidConfig();
    error UnauthorizedCaller();
    error StaleOraclePrice();
    
    /**
     * @notice Constructor
     * @param _poolManager The Uniswap v4 pool manager
     * @param _vault The LVR shield vault
     * @param _oracle The price oracle
     */
    constructor(
        IPoolManager _poolManager,
        IVault _vault,
        IPriceOracle _oracle
    ) BaseHook(_poolManager) {
        if (address(_vault) == address(0)) revert InvalidVault();
        if (address(_oracle) == address(0)) revert InvalidOracle();
        
        VAULT = _vault;
        ORACLE = _oracle;
        ADMIN = msg.sender;
        
        // Initialize with safe default configuration
        config = Config({
            widenBps: 100,      // 1% volatility threshold for WIDENED
            riskOffBps: 500,    // 5% volatility threshold for RISK_OFF
            staleAfter: 300     // 5 minutes staleness threshold
        });
        
        // Validate hook deployment address
        _validateHookAddress();
    }
    
    /**
     * @notice Validates that the hook is deployed at the correct address
     * @dev Ensures the address matches the expected permission bits
     */
    function _validateHookAddress() private view {
        Hooks.Permissions memory permissions = getHookPermissions();
        address expectedAddress = Hooks.getHookAddress(permissions, address(this));
        
        require(
            address(this) == expectedAddress,
            "HOOK: INVALID_DEPLOYMENT_ADDRESS"
        );
    }
    
    /**
     * @notice Returns the hook permissions
     * @return Hooks.Permissions The permissions struct
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,  // Only afterSwap is enabled
            beforeDonate: false,
            afterDonate: false,
            noOpDelta: false,
            mustSwapInexact: false,
            mustSwapExact: false
        });
    }
    
    /**
     * @notice Hook called after a swap is executed
     * @dev Monitors price changes and triggers vault mode changes on high volatility
     */
    function _afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        bytes32 poolId = key.toId();
        
        // Get current price from oracle with error handling
        (uint256 currentPrice, uint64 oracleTimestamp) = _getOraclePrice(poolId);
        
        if (currentPrice == 0) {
            // Oracle failure - continue without mode change
            return (BaseHook.afterSwap.selector, 0);
        }
        
        PriceState storage state = priceStates[poolId];
        
        // Initialize price state on first swap
        if (!state.initialized) {
            state.lastPriceE18 = uint128(currentPrice);
            state.lastUpdateTime = uint64(block.timestamp);
            state.initialized = true;
            
            emit Signal(poolId, currentPrice, oracleTimestamp, 0);
            return (BaseHook.afterSwap.selector, 0);
        }
        
        // Check for stale oracle price
        if (_isPriceStale(oracleTimestamp)) {
            emit OracleError(poolId, "STALE_PRICE");
            return (BaseHook.afterSwap.selector, 0);
        }
        
        // Calculate volatility
        uint256 volatilityBps = uint256(state.lastPriceE18).bpsDiff(currentPrice);
        
        // Emit signal with volatility data
        emit Signal(poolId, currentPrice, oracleTimestamp, volatilityBps);
        
        // Determine new mode based on volatility
        IVault.Mode targetMode = _determineMode(volatilityBps);
        IVault.Mode currentMode = VAULT.currentMode();
        
        // Apply mode change if needed
        if (targetMode != currentMode && _shouldChangeMode(targetMode, currentMode)) {
            _applyModeChange(poolId, targetMode, volatilityBps);
        }
        
        // Update state
        state.lastPriceE18 = uint128(currentPrice);
        state.lastUpdateTime = uint64(block.timestamp);
        
        return (BaseHook.afterSwap.selector, 0);
    }
    
    /**
     * @notice Updates the configuration
     * @param widenBps New threshold for WIDENED mode
     * @param riskOffBps New threshold for RISK_OFF mode  
     * @param staleAfter New staleness threshold in seconds
     */
    function setConfig(
        uint256 widenBps,
        uint256 riskOffBps,
        uint64 staleAfter
    ) external {
        if (msg.sender != ADMIN) revert UnauthorizedCaller();
        if (widenBps == 0 || widenBps >= riskOffBps) revert InvalidConfig();
        if (riskOffBps >= MAX_BPS) revert InvalidConfig();
        if (staleAfter < MIN_STALE_AFTER || staleAfter > MAX_STALE_AFTER) {
            revert InvalidConfig();
        }
        
        Config memory oldConfig = config;
        
        config = Config({
            widenBps: uint128(widenBps),
            riskOffBps: uint128(riskOffBps),
            staleAfter: staleAfter
        });
        
        emit ConfigUpdated(
            oldConfig.widenBps,
            oldConfig.riskOffBps,
            oldConfig.staleAfter,
            widenBps,
            riskOffBps,
            staleAfter
        );
    }
    
    // Internal helper functions
    
    function _getOraclePrice(bytes32 poolId) private view returns (uint256, uint64) {
        try ORACLE.latestPriceE18(poolId) returns (uint256 price, uint64 timestamp) {
            return (price, timestamp);
        } catch {
            return (0, 0);
        }
    }
    
    function _isPriceStale(uint64 oracleTimestamp) private view returns (bool) {
        return block.timestamp > oracleTimestamp + config.staleAfter;
    }
    
    function _determineMode(uint256 volatilityBps) private view returns (IVault.Mode) {
        if (volatilityBps >= config.riskOffBps) {
            return IVault.Mode.RISK_OFF;
        } else if (volatilityBps >= config.widenBps) {
            return IVault.Mode.WIDENED;
        } else {
            return IVault.Mode.NORMAL;
        }
    }
    
    function _shouldChangeMode(
        IVault.Mode targetMode,
        IVault.Mode currentMode
    ) private pure returns (bool) {
        // Always escalate to higher risk modes
        if (uint8(targetMode) > uint8(currentMode)) {
            return true;
        }
        
        // De-escalate only when volatility has decreased significantly
        if (uint8(targetMode) < uint8(currentMode)) {
            // Could add additional logic here for hysteresis
            return true;
        }
        
        return false;
    }
    
    function _applyModeChange(
        bytes32 poolId,
        IVault.Mode targetMode,
        uint256 volatilityBps
    ) private {
        string memory reason = _formatReason(targetMode, volatilityBps);
        
        try VAULT.applyMode(targetMode, uint64(block.timestamp), reason) {
            // Success - mode changed
        } catch {
            // Log error but don't revert the swap
            emit OracleError(poolId, "MODE_CHANGE_FAILED");
        }
    }
    
    function _formatReason(
        IVault.Mode mode,
        uint256 volatilityBps
    ) private pure returns (string memory) {
        if (mode == IVault.Mode.RISK_OFF) {
            return "High volatility detected";
        } else if (mode == IVault.Mode.WIDENED) {
            return "Moderate volatility detected";
        } else {
            return "Volatility normalized";
        }
    }
}