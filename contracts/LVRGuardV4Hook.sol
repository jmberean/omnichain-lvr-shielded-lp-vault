// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BaseHook} from "v4-periphery/BaseHook.sol";

import {ILVRGuardVault, Mode} from "./interfaces/ILVRGuardVault.sol";

contract LVRGuardV4Hook is BaseHook {
    using PoolIdLibrary for PoolKey;

    uint256 public constant DWELL_TIME = 12; // 1 block (12s) dwell time
    uint256 public lastModeChangeTimestamp;

    ILVRGuardVault public immutable vault;

    constructor(ILVRGuardVault _vault) BaseHook(IPoolManager(address(0))) {
        vault = _vault;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({flags: Hooks.AFTER_SWAP_FLAG});
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        int128 delta
    ) internal override returns (bytes4, int128) {
        if (block.timestamp < lastModeChangeTimestamp + DWELL_TIME) {
            // Hysteresis: Dwell time has not passed, do nothing.
            return (Hooks.NO_OP_SELECTOR, 0);
        }

        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96,) = StateLibrary.getSlot0(poolManager, poolId);

        // This calculation is a simplified proxy. A real CWI would be more complex.
        uint256 cwi = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) >> 192;

        vault.signal(int256(delta), cwi);

        Mode currentMode = vault.mode();
        if (currentMode != vault.lastAppliedMode()) {
            lastModeChangeTimestamp = block.timestamp;
            vault.applyMode(currentMode);
        }

        return (Hooks.NO_OP_SELECTOR, 0);
    }
}