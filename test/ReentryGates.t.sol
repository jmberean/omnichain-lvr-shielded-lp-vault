// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {LVRGuardV4Hook} from "../contracts/LVRGuardV4Hook.sol";
import {LVRVault} from "../contracts/Vault.sol";
contract ReentryGatesTest is Test {
    function _dummyKey() internal pure returns (PoolKey memory key) {
        key = PoolKey({ currency0: Currency.wrap(address(0x1)), currency1: Currency.wrap(address(0x2)), fee: 3000, tickSpacing: 20, hooks: address(0) });
    }
    function test_previewPlacement_homeVsRecenter() public {
        IPoolManager pm = IPoolManager(address(0xBEEF));
        LVRVault vault = new LVRVault();
        LVRGuardV4Hook.Config memory cfg = LVRGuardV4Hook.Config({
            ewmaAlphaPPM: 200_000, kSigma: 3, dwellSec: 60, minFlipIntervalSec: 30, homeTtlSec: 3600, recenterWidthMult: 50
        });
        LVRGuardV4Hook hook = new LVRGuardV4Hook(pm, vault, cfg);
        PoolKey memory key = _dummyKey();
        (bool home1, int24 l1, int24 u1) = hook.previewPlacement(key, 1000, 900, 1100, 10);
        assertTrue(home1); assertEq(l1, 900); assertEq(u1, 1100);
        (bool home2, int24 l2, int24 u2) = hook.previewPlacement(key, 2500, 900, 1100, 5);
        assertFalse(home2);
        int24 snapped = 2500 - (2500 % key.tickSpacing);
        assertEq(snapped - 50 * key.tickSpacing, l2);
        assertEq(snapped + 50 * key.tickSpacing, u2);
    }
}


