// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {LVRGuardV4Hook} from "../contracts/LVRGuardV4Hook.sol";
import {LVRVault} from "../contracts/Vault.sol";
contract HookPermissionsTest is Test {
    function test_minedAddressHasAfterSwapOnly() public {
        IPoolManager pm = IPoolManager(address(0xBEEF));
        LVRVault vault = new LVRVault();
        LVRGuardV4Hook.Config memory cfg = LVRGuardV4Hook.Config({
            ewmaAlphaPPM: 200_000, kSigma: 3, dwellSec: 120, minFlipIntervalSec: 60, homeTtlSec: 3600, recenterWidthMult: 50
        });
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        bytes memory ctor = abi.encode(pm, vault, cfg);
        (address mined, bytes32 salt) = HookMiner.find(address(this), flags, type(LVRGuardV4Hook).creationCode, ctor);
        LVRGuardV4Hook hook = new LVRGuardV4Hook{salt: salt}(pm, vault, cfg);
        assertEq(address(hook), mined, "mined!=deployed");
        uint160 a = uint160(address(hook));
        assertTrue((a & uint160(Hooks.AFTER_SWAP_FLAG)) != 0, "afterSwap not set");
        assertFalse((a & uint160(Hooks.BEFORE_SWAP_FLAG)) != 0, "beforeSwap set");
        assertFalse((a & uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG)) != 0, "afterAdd set");
        assertFalse((a & uint160(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)) != 0, "afterRemove set");
    }
}


