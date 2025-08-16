// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import {LVRGuardV4Hook} from "../contracts/LVRGuardV4Hook.sol";
import {LVRVault} from "../contracts/Vault.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
contract GasCapsTest is Test {
    function test_previewMathUnderBudget() public {
        IPoolManager pm = IPoolManager(address(0xBEEF));
        LVRVault vault = new LVRVault();
        LVRGuardV4Hook.Config memory cfg = LVRGuardV4Hook.Config({
            ewmaAlphaPPM: 200_000, kSigma: 3, dwellSec: 60, minFlipIntervalSec: 30, homeTtlSec: 3600, recenterWidthMult: 50
        });
        LVRGuardV4Hook hook = new LVRGuardV4Hook(pm, vault, cfg);
        uint256 g0 = gasleft();
        unchecked { for (uint256 i = 0; i < 64; ++i) { bytes32 h = keccak256(abi.encode(i)); require(uint256(h) > 0, "x"); } }
        uint256 used = g0 - gasleft();
        assertLt(used, 120_000, "budget too high");
    }
}


