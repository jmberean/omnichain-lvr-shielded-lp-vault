// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {Vault} from "../contracts/Vault.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";
import {MockPriceOracle} from "../contracts/oracle/MockPriceOracle.sol";

// Uniswap v4 types (used in permissions assertions / compile sanity)
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

contract LVRShieldHookTest is Test {
    Vault internal vault;
    LVRShieldHook internal hook;
    MockPriceOracle internal oracle;

    address internal admin;
    IPoolManager internal manager;

    // Deterministic test pool id
    bytes32 internal constant POOL_ID = bytes32(uint256(0x1234));

    // Re-declare the Vault event so vm.expectEmit can match it
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

        // Vault now takes admin in constructor
        vault = new Vault(admin);

        // Mock oracle now takes admin in constructor (kept for future tests; not used directly here)
        oracle = new MockPriceOracle(admin);

        // For unit tests we don’t need a real PoolManager; address(0) compiles
        manager = IPoolManager(address(0));

        // Hook now takes (IPoolManager, IVault, admin)
        hook = new LVRShieldHook(manager, IVault(address(vault)), admin);

        // Wire the hook into the vault (onlyHook gating)
        vault.setHook(address(hook));
    }

    function testPermissions() public {
        Hooks.Permissions memory p = hook.getHookPermissions();
        assertTrue(p.beforeSwap, "beforeSwap should be true");
        assertTrue(p.afterSwap, "afterSwap should be true");
        assertFalse(p.beforeSwapReturnDelta, "beforeSwapReturnDelta false");
        assertFalse(p.afterSwapReturnDelta, "afterSwapReturnDelta false");
    }

    function testSetLVRConfigAndReadBack() public {
        // setLVRConfig(bytes32 poolId, uint24 widenBps, uint24 riskOffBps, uint32 minFlipIntervalSec)
        vm.prank(admin);
        hook.setLVRConfig(POOL_ID, 100, 200, 300);

        (uint24 widenBps, uint24 riskOffBps, uint32 minFlip) = hook.cfg(POOL_ID);
        assertEq(widenBps, 100, "widenBps");
        assertEq(riskOffBps, 200, "riskOffBps");
        assertEq(minFlip, 300, "minFlipIntervalSec");
    }

    function testAdminApplyModeEmitsOnVault() public {
        // Expect the Vault to emit ModeApplied with our arguments
        vm.expectEmit(true, false, false, true, address(vault));
        emit ModeApplied(
            POOL_ID,
            uint8(IVault.Mode.WIDENED),
            uint64(1),
            "demo",
            int24(0),
            int24(0)
        );

        vm.prank(admin);
        hook.adminApplyModeForDemo(POOL_ID, IVault.Mode.WIDENED, 1, "demo", 0, 0);
    }
}
