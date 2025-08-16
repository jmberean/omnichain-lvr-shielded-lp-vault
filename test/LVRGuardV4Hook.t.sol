// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {BaseHookTest} from "v4-periphery/test/BaseHookTest.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {LVRGuardV4Hook} from "../contracts/LVRGuardV4Hook.sol";
import {LVRGuardVault} from "../contracts/LVRGuardVault.sol";
import {Mode} from "../contracts/interfaces/ILVRGuardVault.sol";

contract LVRGuardV4HookTest is BaseHookTest {
    LVRGuardVault internal vault;
    LVRGuardV4Hook internal hook;

    event Signal(address indexed sender, uint256 blockTimestamp, int256 netDelta, uint256 cwi);

    function setUp() public override {
        // This setup from BaseHookTest deploys a PoolManager and currencies
        super.setUp();

        // Deploy our vault and hook
        vault = new LVRGuardVault();
        // The hook miner is not needed for testing logic, only for deployment address
        hook = new LVRGuardV4Hook(vault);

        // Initialize a pool with our hook
        // Hooks must be approved by the pool manager before use
        poolManager.setHookPermissions(address(hook), Hooks.Permissions({flags: Hooks.AFTER_SWAP_FLAG}));
        key = _createPool(address(hook));
        (currency0, currency1) = (key.currency0, key.currency1);
    }

    function test_HasCorrectPermissions() public {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.flags == Hooks.AFTER_SWAP_FLAG, "permission mismatch");
    }

    function testFuzz_AfterSwapTriggersSignal(int128 swapAmount) public {
        // Ensure swap is realistic
        swapAmount = int128(bound(swapAmount, -1e18, 1e18));
        if (swapAmount == 0) return;

        _addLiquidity(1 ether);

        // Expect the hook to cause the vault to emit a Signal event
        vm.expectEmit(true, true, true, true, address(vault));
        emit Signal(address(hook), block.timestamp, swapAmount, vault.cwi());

        // Perform the swap
        _swap(swapAmount);
    }

    function test_HysteresisBlocksRapidSignals() public {
        _addLiquidity(1 ether);

        // First swap should succeed and emit a signal
        vm.expectEmit(true, true, true, true, address(vault));
        emit Signal(address(hook), block.timestamp, 1e17, vault.cwi());
        _swap(1e17);

        // Change mode to trigger dwell timer
        vault.applyMode(Mode.SHIELDED);
        assertEq(uint256(hook.lastModeChangeTimestamp()), block.timestamp);

        // Second swap immediately after should NOT emit a signal due to dwell time
        vm.expectNoEmits();
        _swap(-1e17);
    }

    function test_HysteresisAllowsSignalAfterDwellTime() public {
        _addLiquidity(1 ether);
        _swap(1e17); // Initial swap

        // Change mode to trigger dwell timer
        vault.applyMode(Mode.SHIELDED);
        uint256 dwellTime = hook.DWELL_TIME();
        assertEq(hook.lastModeChangeTimestamp(), block.timestamp);

        // Advance time past the dwell period
        vm.warp(block.timestamp + dwellTime + 1);

        // This swap should now be processed and emit a signal
        vm.expectEmit(true, true, true, true, address(vault));
        emit Signal(address(hook), block.timestamp, -1e17, vault.cwi());
        _swap(-1e17);
    }

    function test_GasConsumptionAfterSwap() public {
        _addLiquidity(10 ether);

        uint256 gasStart = gasleft();
        _swap(1 ether);
        uint256 gasEnd = gasleft();

        uint256 gasUsed = gasStart - gasEnd;

        // Note: This gas value is sensitive to compiler settings and EVM version.
        // It's a placeholder to catch significant regressions.
        uint256 expectedGasCap = 60000;
        assertTrue(gasUsed < expectedGasCap, "Gas usage exceeded cap");
    }
}