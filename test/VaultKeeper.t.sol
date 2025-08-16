// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {Vault} from "../contracts/Vault.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";

contract VaultKeeperTest is Test {
    Vault internal vault;

    address internal admin;
    address internal keeper;
    address internal stranger;

    // use a deterministic pool id for tests
    bytes32 internal constant POOL_ID = bytes32(uint256(0xC0FFEE));

    // Re-declare Vault events for expectEmit()
    event ModeApplied(
        bytes32 indexed poolId,
        uint8 mode,
        uint64 epoch,
        string reason,
        int24 centerTick,
        int24 halfWidthTicks
    );

    event LiquidityAction(
        bytes32 indexed poolId,
        uint8 mode,
        int24 centerTick,
        int24 halfWidthTicks,
        uint64 epoch,
        string action
    );

    function setUp() public {
        admin = address(this);              // test contract is admin
        keeper = makeAddr("keeper");
        stranger = makeAddr("stranger");

        vault = new Vault(admin);

        // For onlyHook gating, set the hook to this test contract so calls from here are authorized
        vault.setHook(address(this));
        vault.setKeeper(keeper);
    }

    // -------- onlyHook gating --------
    function testOnlyHookCannotBeCalledByOthers() public {
        // Have a non-hook address attempt to call applyMode -> expect revert
        vm.prank(stranger);
        vm.expectRevert(bytes("VAULT:NOT_HOOK"));
        vault.applyMode(
            POOL_ID,
            IVault.Mode.NORMAL,
            uint64(1),
            "unauth",
            int24(0),
            int24(0)
        );
    }

    // -------- applyMode emits + home tracking --------
    function testApplyModeEmitsAndUpdatesHomeWhenHintsProvided() public {
        // Expect ModeApplied with exact args
        vm.expectEmit(true, false, false, true, address(vault));
        emit ModeApplied(
            POOL_ID,
            uint8(IVault.Mode.WIDENED),
            uint64(7),
            "recenter",
            int24(100),
            int24(50)
        );

        // Call as hook (this contract is the hook)
        vault.applyMode(
            POOL_ID,
            IVault.Mode.WIDENED,
            uint64(7),
            "recenter",
            int24(100),
            int24(50)
        );

        // getHome should reflect the hints
        (int24 c, int24 w) = vault.getHome(POOL_ID);
        assertEq(c, int24(100), "home.centerTick");
        assertEq(w, int24(50), "home.halfWidthTicks");
    }

    function testApplyModeDoesNotChangeHomeWhenHintsZero() public {
        // seed a home placement
        vault.applyMode(
            POOL_ID,
            IVault.Mode.NORMAL,
            uint64(1),
            "seed",
            int24(111),
            int24(22)
        );

        // apply with zero hints -> home should remain unchanged
        vault.applyMode(
            POOL_ID,
            IVault.Mode.RISK_OFF,
            uint64(2),
            "risk",
            int24(0),
            int24(0)
        );

        (int24 c, int24 w) = vault.getHome(POOL_ID);
        assertEq(c, int24(111), "home.centerTick unchanged");
        assertEq(w, int24(22), "home.halfWidthTicks unchanged");
    }

    // -------- keeperRebalance gating + emit + home tracking --------
    function testKeeperRebalanceOnlyKeeper() public {
        vm.prank(stranger);
        vm.expectRevert(bytes("VAULT:NOT_KEEPER"));
        vault.keeperRebalance(
            POOL_ID,
            int24(0),
            int24(0),
            "noop",
            uint8(IVault.Mode.NORMAL),
            uint64(1)
        );
    }

    function testKeeperRebalanceEmitsAndTracksHome() public {
        // Expect LiquidityAction from the keeper call
        vm.expectEmit(true, false, false, true, address(vault));
        emit LiquidityAction(
            POOL_ID,
            uint8(IVault.Mode.WIDENED),
            int24(88),
            int24(33),
            uint64(9),
            "recenter"
        );

        vm.prank(keeper);
        vault.keeperRebalance(
            POOL_ID,
            int24(88),
            int24(33),
            "recenter",
            uint8(IVault.Mode.WIDENED),
            uint64(9)
        );

        // Home should now reflect keeper placement
        (int24 c, int24 w) = vault.getHome(POOL_ID);
        assertEq(c, int24(88), "home.centerTick from keeper");
        assertEq(w, int24(33), "home.halfWidthTicks from keeper");
    }
}
