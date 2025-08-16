// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager as V4PoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Vault} from "../contracts/Vault.sol";
import {LVRGuardV4Hook} from "../contracts/LVRGuardV4Hook.sol";

contract HookPermissionsTest is Test {
    function test_GetHookPermissions_afterSwapOnly() public {
        Vault v = new Vault(address(this));
        LVRGuardV4Hook.Config memory cfg = LVRGuardV4Hook.Config({
            minFlipInterval: 60, dwellBlocks: 2, confirmBlocks: 2, homeWidthTicks: 120, recentreWidthMult: 3
        });
        LVRGuardV4Hook h = new LVRGuardV4Hook(V4PoolManager(address(1)), v, cfg);

        Hooks.Permissions memory p = h.getHookPermissions();
        assertTrue(p.afterSwap);
        assertFalse(p.beforeSwap);
        assertFalse(p.beforeInitialize);
        assertFalse(p.afterInitialize);
        assertFalse(p.beforeAddLiquidity);
        assertFalse(p.afterAddLiquidity);
        assertFalse(p.beforeRemoveLiquidity);
        assertFalse(p.afterRemoveLiquidity);
    }

    function test_Vault_onlyHook() public {
        Vault v = new Vault(address(this));
        vm.expectRevert(bytes("onlyHook"));
        v.notifyMode(bytes32(uint256(0x01)), 1, 0);
    }
}
