// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Vault} from "../contracts/Vault.sol";
import {LVRGuardV4Hook} from "../contracts/LVRGuardV4Hook.sol";
import {IPoolManager as V4PoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract ReentryGatesTest is Test {
    function test_previewBand_aligns() public {
        Vault v = new Vault(address(this));
        LVRGuardV4Hook.Config memory cfg = LVRGuardV4Hook.Config({
            minFlipInterval: 60, dwellBlocks: 2, confirmBlocks: 2, homeWidthTicks: 120, recentreWidthMult: 3
        });
        LVRGuardV4Hook h = new LVRGuardV4Hook(V4PoolManager(address(1)), v, cfg);

        (int24 lo, int24 hi) = h.previewBand(101, 10);
        assertEq(lo, -20);  // 100 - 120
        assertEq(hi, 220);  // 100 + 120
    }
}
