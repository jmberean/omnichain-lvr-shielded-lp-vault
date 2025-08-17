// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Uniswap v4 core - types
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";  // THIS IS THE FIX!

// Interfaces
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

// Libraries
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

// v4-periphery BaseHook
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

// Local
import {IVault} from "../../interfaces/IVault.sol";
import {IPriceOracle} from "../../oracle/IPriceOracle.sol";

/// @title LVR Shield Hook for Uniswap v4
/// @notice Implements dynamic liquidity positioning based on LVR risk signals
/// @dev Uses address-encoded permissions for beforeSwap, afterSwap, afterAddLiquidity
contract LVRShieldHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using BalanceDeltaLibrary for BalanceDelta;

    // ============ Constants ============
    uint256 constant EWMA_ALPHA = 200; // Alpha = 0.02 (2%) for EWMA updates
    uint256 constant SIGMA_WINDOW = 20; // Window for sigma calculation
    uint256 constant BPS_BASE = 10_000;
    
    // ============ Immutables ============
    IVault public immutable VAULT;
    address public immutable ADMIN;
    IPriceOracle public immutable ORACLE;

    // ============ Types ============
    enum Mode {
        NORMAL,    // 0: Normal operations, tight range
        WIDENED,   // 1: Widened range due to elevated volatility
        RISK_OFF   // 2: Risk-off mode, maximum protection
    }

    struct PoolState {
        Mode currentMode;
        uint64 lastModeFlip;
        uint64 epoch;
        int24 lastSpotTick;
        int24 ewmaTick;
        uint24 sigmaTicks;
        uint8 confirmationCount;
        bool hasDwelled;
        HomePlacement home;
        uint256[] recentTicks; // Circular buffer for sigma calc
        uint8 tickIndex;
    }

    struct HomePlacement {
        int24 centerTick;
        int24 halfWidthTicks;
        uint64 timestamp;
    }

    struct LVRConfig {
        uint16 widenBps;           // Threshold to enter WIDENED (e.g., 100 = 1%)
        uint16 riskOffBps;         // Threshold to enter RISK_OFF (e.g., 500 = 5%)
        uint16 exitThresholdBps;   // Lower threshold for exiting modes (hysteresis)
        uint32 dwellSec;           // Minimum time in mode before transition
        uint8 confirmations;       // Required consecutive signals
        uint32 minFlipInterval;    // Minimum seconds between mode changes
        int24 homeToleranceTicks;  // Distance from home before RECENTER
        uint32 homeTtlSec;         // Home placement TTL
        uint16 kTimes10;           // Multiplier for sigma (e.g., 15 = 1.5x)
        int24 minTicks;            // Minimum half-width
        int24 maxTicks;            // Maximum half-width
    }

    // ============ State ============
    LVRConfig public cfg;
    mapping(PoolId => PoolState) public poolStates;
    mapping(PoolId => bytes32) public poolOracles; // Map pools to oracle price IDs

    // ============ Events ============
    event Signal(PoolId indexed poolId, int24 spotTick, int24 ewmaTick, uint24 sigmaTicks);
    event ModeChanged(PoolId indexed poolId, Mode oldMode, Mode newMode, uint64 epoch, string reason);
    event HomeRecorded(PoolId indexed poolId, int24 centerTick, int24 halfWidthTicks);
    event ReentryDecision(PoolId indexed poolId, bool useHome, int24 centerTick, int24 halfWidthTicks);
    event Recentered(PoolId indexed poolId, int24 oldCenter, int24 newCenter, string reason);
    event ConfigUpdated(uint16 widenBps, uint16 riskOffBps, uint32 minFlipInterval);

    // ============ Constructor ============
    constructor(
        IPoolManager manager,
        IVault vault,
        IPriceOracle oracle,
        address admin
    ) BaseHook(manager) {
        require(address(vault) != address(0), "vault=0");
        require(address(oracle) != address(0), "oracle=0");
        require(admin != address(0), "admin=0");
        
        VAULT = vault;
        ORACLE = oracle;
        ADMIN = admin;

        // Initialize default config
        cfg = LVRConfig({
            widenBps: 100,           // 1% threshold
            riskOffBps: 500,         // 5% threshold  
            exitThresholdBps: 70,    // 0.7% exit threshold
            dwellSec: 300,           // 5 min dwell
            confirmations: 3,        // 3 consecutive signals
            minFlipInterval: 600,    // 10 min between flips
            homeToleranceTicks: 100, // 100 tick tolerance
            homeTtlSec: 3600,        // 1 hour TTL
            kTimes10: 15,            // 1.5x sigma
            minTicks: 50,            // Min width
            maxTicks: 500            // Max width
        });

        // Validate hook permissions match address
        Hooks.validateHookPermissions(this, getHookPermissions());
    }

    // ============ Hook Permissions ============
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,  // Track liquidity events
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,         // Pre-swap checks
            afterSwap: true,          // Post-swap state updates
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ============ Hook Callbacks (BaseHook overrides) ============
    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,  // Now properly imported!
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId poolId = key.toId();
        
        // Check oracle freshness if configured
        bytes32 oracleId = poolOracles[poolId];
        if (oracleId != bytes32(0)) {
            (uint256 price, uint64 publishTime) = ORACLE.getPriceE18(oracleId);
            require(block.timestamp - publishTime <= 60, "stale oracle");
        }
        
        emit Signal(poolId, poolStates[poolId].lastSpotTick, poolStates[poolId].ewmaTick, poolStates[poolId].sigmaTicks);
        
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,  // Now properly imported!
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        PoolId poolId = key.toId();
        
        // Get current tick from pool
        (, int24 currentTick,,) = poolManager.getSlot0(poolId);
        
        // Update state and check for mode transitions
        _updatePoolState(poolId, currentTick);
        _checkModeTransition(poolId);
        
        return (BaseHook.afterSwap.selector, 0);
    }

    function _afterAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        // Track liquidity changes for telemetry
        emit Signal(key.toId(), 0, 0, 0);
        return (BaseHook.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    // ============ Core Logic ============
    function _updatePoolState(PoolId poolId, int24 currentTick) internal {
        PoolState storage state = poolStates[poolId];
        
        // Initialize if first update
        if (state.ewmaTick == 0) {
            state.ewmaTick = currentTick;
            state.lastSpotTick = currentTick;
            state.recentTicks = new uint256[](SIGMA_WINDOW);
        }
        
        // Update EWMA: ewma = alpha * current + (1 - alpha) * ewma
        int256 ewmaUpdate = (int256(currentTick) * int256(EWMA_ALPHA) + 
                             int256(state.ewmaTick) * (10000 - int256(EWMA_ALPHA))) / 10000;
        state.ewmaTick = int24(ewmaUpdate);
        
        // Update circular buffer for sigma calculation
        state.recentTicks[state.tickIndex] = uint256(int256(currentTick));
        state.tickIndex = uint8((state.tickIndex + 1) % SIGMA_WINDOW);
        
        // Calculate sigma (standard deviation of recent ticks)
        state.sigmaTicks = _calculateSigma(state.recentTicks, state.ewmaTick);
        
        state.lastSpotTick = currentTick;
    }

    function _calculateSigma(uint256[] memory ticks, int24 mean) internal pure returns (uint24) {
        uint256 sumSquares = 0;
        uint256 count = 0;
        
        for (uint256 i = 0; i < ticks.length; i++) {
            if (ticks[i] != 0) { // Skip uninitialized slots
                int256 diff = int256(ticks[i]) - int256(mean);
                sumSquares += uint256(diff * diff);
                count++;
            }
        }
        
        if (count == 0) return 0;
        
        // Simple integer square root approximation
        uint256 variance = sumSquares / count;
        uint256 sigma = _sqrt(variance);
        
        return uint24(sigma);
    }

    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    function _checkModeTransition(PoolId poolId) internal {
        PoolState storage state = poolStates[poolId];
        
        // Check flip interval gate
        if (block.timestamp < state.lastModeFlip + cfg.minFlipInterval) {
            return;
        }
        
        // Calculate deviation from EWMA
        uint256 deviation = _abs(state.lastSpotTick - state.ewmaTick);
        uint256 threshold = _getModeThreshold(state.currentMode);
        
        Mode targetMode = _determineTargetMode(deviation, state.currentMode);
        
        if (targetMode != state.currentMode) {
            // Check dwell time
            if (!state.hasDwelled && block.timestamp >= state.lastModeFlip + cfg.dwellSec) {
                state.hasDwelled = true;
            }
            
            // Check confirmations
            if (state.hasDwelled) {
                state.confirmationCount++;
                
                if (state.confirmationCount >= cfg.confirmations) {
                    _transitionMode(poolId, targetMode);
                }
            }
        } else {
            // Reset confirmations if signal lost
            state.confirmationCount = 0;
        }
    }

    function _determineTargetMode(uint256 deviationTicks, Mode currentMode) internal view returns (Mode) {
        // Apply hysteresis - use lower threshold when exiting elevated modes
        uint256 widenThreshold = currentMode == Mode.NORMAL ? 
            uint256(cfg.widenBps) : uint256(cfg.exitThresholdBps);
        uint256 riskOffThreshold = currentMode <= Mode.WIDENED ? 
            uint256(cfg.riskOffBps) : uint256(cfg.exitThresholdBps);
        
        // Convert basis points to tick threshold
        if (deviationTicks * BPS_BASE >= riskOffThreshold * 100) {
            return Mode.RISK_OFF;
        } else if (deviationTicks * BPS_BASE >= widenThreshold * 100) {
            return Mode.WIDENED;
        } else {
            return Mode.NORMAL;
        }
    }

    function _getModeThreshold(Mode mode) internal view returns (uint256) {
        if (mode == Mode.RISK_OFF) return cfg.riskOffBps;
        if (mode == Mode.WIDENED) return cfg.widenBps;
        return cfg.exitThresholdBps;
    }

    function _transitionMode(PoolId poolId, Mode newMode) internal {
        PoolState storage state = poolStates[poolId];
        Mode oldMode = state.currentMode;
        
        state.currentMode = newMode;
        state.lastModeFlip = uint64(block.timestamp);
        state.epoch++;
        state.confirmationCount = 0;
        state.hasDwelled = false;
        
        // Calculate placement for new mode
        (int24 centerTick, int24 halfWidthTicks) = _calculatePlacement(poolId, newMode);
        
        // Apply mode via Vault
        bytes32 poolIdBytes = PoolId.unwrap(poolId);
        string memory reason = _getModeReason(oldMode, newMode);
        
        VAULT.applyMode(
            poolIdBytes,
            IVault.Mode(uint8(newMode)),
            state.epoch,
            reason,
            centerTick,
            halfWidthTicks
        );
        
        emit ModeChanged(poolId, oldMode, newMode, state.epoch, reason);
        
        // Record home on entry to NORMAL
        if (newMode == Mode.NORMAL) {
            _recordHome(poolId, centerTick, halfWidthTicks);
        }
    }

    function _calculatePlacement(
        PoolId poolId,
        Mode mode
    ) internal returns (int24 centerTick, int24 halfWidthTicks) {
        PoolState storage state = poolStates[poolId];
        
        // Center on EWMA
        centerTick = state.ewmaTick;
        
        // Calculate width based on mode and sigma
        uint256 baseWidth = uint256(state.sigmaTicks) * uint256(cfg.kTimes10) / 10;
        
        if (mode == Mode.RISK_OFF) {
            halfWidthTicks = int24(int256(baseWidth * 3)); // 3x wider in risk-off
        } else if (mode == Mode.WIDENED) {
            halfWidthTicks = int24(int256(baseWidth * 2)); // 2x wider when widened
        } else {
            // NORMAL mode - check for HOME vs RECENTER
            if (_shouldUseHome(poolId)) {
                HomePlacement memory home = state.home;
                centerTick = home.centerTick;
                halfWidthTicks = home.halfWidthTicks;
                emit ReentryDecision(poolId, true, centerTick, halfWidthTicks);
                return (centerTick, halfWidthTicks);
            }
            halfWidthTicks = int24(int256(baseWidth));
        }
        
        // Apply bounds
        if (halfWidthTicks < cfg.minTicks) halfWidthTicks = cfg.minTicks;
        if (halfWidthTicks > cfg.maxTicks) halfWidthTicks = cfg.maxTicks;
        
        // Snap to tick spacing (assumed to be 10 for 5bps pools)
        centerTick = _snapToSpacing(centerTick, 10);
        halfWidthTicks = _snapToSpacing(halfWidthTicks, 10);
        
        emit ReentryDecision(poolId, false, centerTick, halfWidthTicks);
    }

    function _shouldUseHome(PoolId poolId) internal view returns (bool) {
        PoolState storage state = poolStates[poolId];
        HomePlacement memory home = state.home;
        
        // No home set
        if (home.timestamp == 0) return false;
        
        // Home expired
        if (block.timestamp > home.timestamp + cfg.homeTtlSec) return false;
        
        // Too far from home
        uint256 distance = _abs(state.ewmaTick - home.centerTick);
        if (distance > uint256(uint24(cfg.homeToleranceTicks))) return false;
        
        return true;
    }

    function _recordHome(PoolId poolId, int24 centerTick, int24 halfWidthTicks) internal {
        poolStates[poolId].home = HomePlacement({
            centerTick: centerTick,
            halfWidthTicks: halfWidthTicks,
            timestamp: uint64(block.timestamp)
        });
        emit HomeRecorded(poolId, centerTick, halfWidthTicks);
    }

    function _snapToSpacing(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 remainder = tick % spacing;
        if (remainder < 0) remainder += spacing;
        
        if (remainder < spacing / 2) {
            return tick - remainder;
        } else {
            return tick + (spacing - remainder);
        }
    }

    function _abs(int24 x) internal pure returns (uint256) {
        return x < 0 ? uint256(int256(-x)) : uint256(int256(x));
    }

    function _getModeReason(Mode from, Mode to) internal pure returns (string memory) {
        if (to == Mode.RISK_OFF) return "risk-escalation";
        if (to == Mode.WIDENED) return "volatility-increase";
        if (to == Mode.NORMAL && from == Mode.WIDENED) return "volatility-decrease";
        if (to == Mode.NORMAL && from == Mode.RISK_OFF) return "risk-normalization";
        return "mode-change";
    }

    // ============ Admin Functions ============
    function setLVRConfig(
        uint16 widenBps,
        uint16 riskOffBps,
        uint32 minFlipInterval
    ) external {
        require(msg.sender == ADMIN, "not admin");
        require(widenBps > 0 && widenBps < riskOffBps, "invalid thresholds");
        
        cfg.widenBps = widenBps;
        cfg.riskOffBps = riskOffBps;
        cfg.minFlipInterval = minFlipInterval;
        
        emit ConfigUpdated(widenBps, riskOffBps, minFlipInterval);
    }

    function setPoolOracle(PoolId poolId, bytes32 oracleId) external {
        require(msg.sender == ADMIN, "not admin");
        poolOracles[poolId] = oracleId;
    }

    function setAdvancedConfig(
        uint16 exitThresholdBps,
        uint32 dwellSec,
        uint8 confirmations,
        int24 homeToleranceTicks,
        uint32 homeTtlSec,
        uint16 kTimes10,
        int24 minTicks,
        int24 maxTicks
    ) external {
        require(msg.sender == ADMIN, "not admin");
        require(exitThresholdBps < cfg.widenBps, "exit > entry");
        
        cfg.exitThresholdBps = exitThresholdBps;
        cfg.dwellSec = dwellSec;
        cfg.confirmations = confirmations;
        cfg.homeToleranceTicks = homeToleranceTicks;
        cfg.homeTtlSec = homeTtlSec;
        cfg.kTimes10 = kTimes10;
        cfg.minTicks = minTicks;
        cfg.maxTicks = maxTicks;
    }

    // ============ Demo Helper ============
    function adminApplyModeForDemo(
        PoolId poolId,
        IVault.Mode mode,
        uint64 epoch,
        string calldata reason,
        int24 centerTick,
        int24 halfWidthTicks
    ) external {
        require(msg.sender == ADMIN, "not admin");
        bytes32 pid = PoolId.unwrap(poolId);
        VAULT.applyMode(pid, mode, epoch, reason, centerTick, halfWidthTicks);
        emit Signal(poolId, centerTick, centerTick, uint24(halfWidthTicks));
    }
}