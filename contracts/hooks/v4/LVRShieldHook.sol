// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

library LVRMath {
    function clamp(uint24 v, uint24 lo, uint24 hi) internal pure returns (uint24) {
        return v < lo ? lo : (v > hi ? hi : v);
    }
}

contract LVRShieldHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    struct LVRConfig {
        uint24 baseFee;
        uint24 maxFee;
        uint32 volatilityWindow;
        uint256 lvrSensitivity;
    }

    mapping(PoolId => LVRConfig) public lvrConfigs;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory p) {
        p.beforeSwap = true;
        p.afterSwap = true;
        p.afterAddLiquidity = true;
        p.afterSwapReturnDelta = true;
    }

    function setLVRConfig(PoolKey calldata key, LVRConfig calldata cfg) external {
        lvrConfigs[key.toId()] = cfg;
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        uint24 adjusted = _calculateLVRAdjustedFee(key);
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, adjusted);
    }

    function _calculateLVRAdjustedFee(PoolKey calldata key) internal view returns (uint24) {
        LVRConfig memory c = lvrConfigs[key.toId()];
        uint24 base = c.baseFee == 0 ? 3000 : c.baseFee;
        uint24 maxf = c.maxFee == 0 ? 10000 : c.maxFee;
        uint24 bump = uint24((c.lvrSensitivity / 1e16) % 700);
        return LVRMath.clamp(base + bump, base, maxf);
    }
}
