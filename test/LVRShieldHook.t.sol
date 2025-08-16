// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {Vault} from "../contracts/Vault.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";
import {MockPriceOracle} from "../contracts/oracle/MockPriceOracle.sol";
import {HookCreate2Factory} from "../contracts/utils/HookCreate2Factory.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

contract LVRShieldHookTest is Test {
    Vault internal vault;
    LVRShieldHook internal hook;
    MockPriceOracle internal oracle;

    address internal admin;
    IPoolManager internal manager;

    bytes32 internal constant POOL_ID = bytes32(uint256(0x1234));

    event ModeApplied(
        bytes32 indexed poolId,
        uint8 mode,
        uint64 epoch,
        string reason,
        int24 centerTick,
        int24 halfWidthTicks
    );

    function setUp() public {
        admin = address(this);
        vault = new Vault(admin);
        oracle = new MockPriceOracle(admin);
        manager = IPoolManager(address(0));

        // CREATE2 factory
        HookCreate2Factory factory = new HookCreate2Factory();

        // Build init code for LVRShieldHook(manager, vault, admin)
        bytes memory initCode = abi.encodePacked(
            type(LVRShieldHook).creationCode,
            abi.encode(manager, IVault(address(vault)), admin)
        );
        bytes32 initHash = keccak256(initCode);

        // Find salt => predicted address ends with 0x0000 (works for all-false permissions)
        bytes32 salt;
        address predicted;
        unchecked {
            for (uint256 i = 0;; ++i) {
                salt = bytes32(i);
                predicted = address(uint160(uint(keccak256(abi.encodePacked(
                    bytes1(0xff), address(factory), salt, initHash
                )))));
                if (uint16(uint160(predicted)) == 0) break;
            }
        }

        address deployed = factory.deploy(initCode, salt);
        require(deployed == predicted, "DEPLOY_ADDR_MISMATCH");
        hook = LVRShieldHook(deployed);

        vault.setHook(address(hook));
    }

    function testPermissions() public view {
        Hooks.Permissions memory p = hook.getHookPermissions();
        assertFalse(p.beforeSwap);
        assertFalse(p.afterSwap);
        assertFalse(p.beforeSwapReturnDelta);
        assertFalse(p.afterSwapReturnDelta);
    }

    function testSetLVRConfigAndReadBack() public {
        vm.prank(admin);
        hook.setLVRConfig(POOL_ID, 100, 200, 300);
        (uint24 w, uint24 r, uint32 m) = hook.cfg(POOL_ID);
        assertEq(w, 100);
        assertEq(r, 200);
        assertEq(m, 300);
    }

    function testAdminApplyModeEmitsOnVault() public {
        vm.expectEmit(true, false, false, true, address(vault));
        emit ModeApplied(POOL_ID, uint8(IVault.Mode.WIDENED), 1, "demo", 0, 0);
        vm.prank(admin);
        hook.adminApplyModeForDemo(POOL_ID, IVault.Mode.WIDENED, 1, "demo", 0, 0);
    }
}
