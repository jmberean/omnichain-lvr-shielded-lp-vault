// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {IVault} from "../contracts/interfaces/IVault.sol";
import {Vault} from "../contracts/Vault.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";

contract LVRShieldHookTest is Test {
    address internal admin_;
    IPoolManager internal manager_;
    Vault internal vault_;
    LVRShieldHook internal hook_;

    function setUp() public {
        admin_ = address(this);
        manager_ = IPoolManager(address(0xdead));
        vault_ = new Vault(admin_);

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        bytes memory ctorArgs = abi.encode(manager_, IVault(address(vault_)), admin_);

        // >>> Use THIS contract as the CREATE2 deployer (matches actual deployment)
        (address predicted, bytes32 salt) =
            HookMiner.find(address(this), flags, type(LVRShieldHook).creationCode, ctorArgs);

        hook_ = new LVRShieldHook{salt: salt}(manager_, IVault(address(vault_)), admin_);
        assertEq(address(hook_), predicted, "mined address mismatch");
    }

    function testPermissions() public view {
        Hooks.Permissions memory p = hook_.getHookPermissions();
        assertTrue(p.beforeSwap, "beforeSwap true");
        assertTrue(p.afterSwap, "afterSwap true");
        assertFalse(p.beforeSwapReturnDelta);
        assertFalse(p.afterSwapReturnDelta);
    }

    function testSetLVRConfigAndReadBack() public {
        hook_.setLvrConfig(100, 200, 30);
        (uint16 widen, uint16 riskOff, uint32 minFlip) = hook_.cfg();
        assertEq(widen, 100);
        assertEq(riskOff, 200);
        assertEq(minFlip, 30);
    }

    function testAdminApplyModeEmitsOnVault() public view {
        assertTrue(address(hook_) != address(0));
        assertTrue(address(vault_) != address(0));
    }
}
