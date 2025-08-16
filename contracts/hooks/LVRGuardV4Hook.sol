// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Use v4-periphery's version of v4-core for compatibility with BaseHook
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolSwapParams.sol";
import {IVault} from "../interfaces/IVault.sol";
import {PriceMath} from "../libraries/PriceMath.sol";

contract LVRGuardV4Hook is BaseHook {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using PriceMath for uint256;

    IVault public immutable vault;
    
    mapping(PoolId => uint160) public lastSqrtPriceX96;
    
    uint256 public constant WIDEN_THRESHOLD_BPS = 100;
    uint256 public constant RISK_OFF_THRESHOLD_BPS = 500;
    
    event LVRDetected(
        PoolId indexed poolId,
        uint256 priceDiffBps,
        uint8 newMode
    );

    constructor(IPoolManager _poolManager, IVault _vault) BaseHook(_poolManager) {
        vault = _vault;
        validateHookAddress(this);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, int128) {
        PoolId poolId = key.toId();
        
        // Use StateLibrary with proper syntax
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        
        if (lastSqrtPriceX96[poolId] == 0) {
            lastSqrtPriceX96[poolId] = sqrtPriceX96;
            return (BaseHook.afterSwap.selector, 0);
        }
        
        // Calculate price change
        uint256 lastPrice = uint256(lastSqrtPriceX96[poolId]) ** 2 >> 192;
        uint256 currentPrice = uint256(sqrtPriceX96) ** 2 >> 192;
        uint256 priceDiff = lastPrice.bpsDiff(currentPrice);
        
        // Determine mode
        IVault.Mode targetMode = 
            priceDiff >= RISK_OFF_THRESHOLD_BPS ? IVault.Mode.RISK_OFF :
            priceDiff >= WIDEN_THRESHOLD_BPS ? IVault.Mode.WIDENED :
            IVault.Mode.NORMAL;
        
        // Update vault if mode changed
        IVault.Mode currentMode = vault.currentMode();
        if (targetMode != currentMode) {
            uint64 newEpoch = vault.modeEpoch() + 1;
            bytes32 vaultPoolId = bytes32(PoolId.unwrap(poolId));
            vault.applyMode(targetMode, newEpoch, "LVR detected");
            emit LVRDetected(poolId, priceDiff, uint8(targetMode));
        }
        
        lastSqrtPriceX96[poolId] = sqrtPriceX96;
        return (BaseHook.afterSwap.selector, 0);
    }
}