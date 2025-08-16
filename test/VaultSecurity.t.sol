// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../contracts/Vault.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {LVRGuardV4Hook} from "../contracts/hooks/LVRGuardV4Hook.sol";
import {MockPriceOracle} from "../contracts/mocks/MockPriceOracle.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";

contract VaultSecurityTest is Test {
    using PoolIdLibrary for PoolKey;
    
    Vault vault;
    LVRGuardV4Hook hook;
    MockPriceOracle oracle;
    IPoolManager poolManager;
    
    address admin = address(0x1);
    address keeper = address(0x2);
    address attacker = address(0x666);
    bytes32 poolId = bytes32("TEST_POOL");
    
    function setUp() public {
        // Deploy contracts
        vm.startPrank(admin);
        vault = new Vault(poolId);
        oracle = new MockPriceOracle();
        
        // Deploy mock pool manager and hook
        poolManager = IPoolManager(address(new MockPoolManager()));
        hook = new LVRGuardV4Hook(poolManager, vault, oracle);
        
        // Configure vault
        vault.setHook(address(hook));
        vault.setKeeper(keeper);
        vm.stopPrank();
    }
    
    // ============ Access Control Tests ============
    
    function testOnlyAdminCanSetAdmin() public {
        vm.prank(attacker);
        vm.expectRevert("VAULT: NOT_ADMIN");
        vault.setAdmin(attacker);
        
        vm.prank(admin);
        vault.setAdmin(address(0x3));
        assertEq(vault.admin(), address(0x3));
    }
    
    function testOnlyAdminCanSetHook() public {
        vm.prank(attacker);
        vm.expectRevert("VAULT: NOT_ADMIN");
        vault.setHook(attacker);
        
        vm.prank(admin);
        vault.setHook(address(0x4));
        assertEq(vault.hook(), address(0x4));
    }
    
    function testOnlyAdminCanSetKeeper() public {
        vm.prank(attacker);
        vm.expectRevert("VAULT: NOT_ADMIN");
        vault.setKeeper(attacker);
    }
    
    function testOnlyHookCanApplyMode() public {
        vm.prank(attacker);
        vm.expectRevert("VAULT: NOT_HOOK");
        vault.applyMode(IVault.Mode.WIDENED, 1, "attack");
    }
    
    function testOnlyKeeperCanRebalance() public {
        vm.prank(attacker);
        vm.expectRevert("VAULT: NOT_KEEPER");
        vault.keeperRebalance(1e18, -1e18, "attack");
    }
    
    function testZeroAddressValidation() public {
        vm.startPrank(admin);
        
        vm.expectRevert("VAULT: ZERO_ADDRESS");
        vault.setAdmin(address(0));
        
        vm.expectRevert("VAULT: ZERO_ADDRESS");
        vault.setHook(address(0));
        
        vm.expectRevert("VAULT: ZERO_ADDRESS");
        vault.setKeeper(address(0));
        
        vm.stopPrank();
    }
    
    // ============ Reentrancy Tests ============
    
    contract ReentrantHook {
        Vault target;
        bool attacked;
        
        constructor(Vault _target) {
            target = _target;
        }
        
        function attack() external {
            target.applyMode(IVault.Mode.WIDENED, 1, "reentrant");
        }
        
        // Callback that attempts reentrancy
        fallback() external {
            if (!attacked) {
                attacked = true;
                target.applyMode(IVault.Mode.RISK_OFF, 2, "reentrant2");
            }
        }
    }
    
    function testReentrancyProtection() public {
        ReentrantHook maliciousHook = new ReentrantHook(vault);
        
        vm.prank(admin);
        vault.setHook(address(maliciousHook));
        
        vm.prank(address(maliciousHook));
        vm.expectRevert(); // Should revert due to reentrancy guard
        maliciousHook.attack();
    }
    
    // ============ Mode Transition Tests ============
    
    function testValidModeTransitions() public {
        vm.startPrank(address(hook));
        
        // NORMAL -> WIDENED (valid)
        vault.applyMode(IVault.Mode.WIDENED, 1, "test");
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.WIDENED));
        
        // WIDENED -> RISK_OFF (valid)
        vm.warp(block.timestamp + 301); // Pass cooldown
        vault.applyMode(IVault.Mode.RISK_OFF, 2, "test");
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.RISK_OFF));
        
        // RISK_OFF -> WIDENED (valid de-escalation)
        vm.warp(block.timestamp + 301);
        vault.applyMode(IVault.Mode.WIDENED, 3, "test");
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.WIDENED));
        
        vm.stopPrank();
    }
    
    function testInvalidModeTransitions() public {
        vm.startPrank(address(hook));
        
        // Set to RISK_OFF first
        vault.applyMode(IVault.Mode.RISK_OFF, 1, "setup");
        vm.warp(block.timestamp + 301);
        
        // RISK_OFF -> NORMAL (invalid - must go through WIDENED)
        vm.expectRevert("VAULT: INVALID_TRANSITION");
        vault.applyMode(IVault.Mode.NORMAL, 2, "invalid");
        
        vm.stopPrank();
    }
    
    function testCooldownPeriod() public {
        vm.startPrank(address(hook));
        
        vault.applyMode(IVault.Mode.WIDENED, 1, "first");
        
        // Try to change mode before cooldown
        vm.expectRevert("VAULT: COOLDOWN_ACTIVE");
        vault.applyMode(IVault.Mode.NORMAL, 2, "too soon");
        
        // Wait for cooldown
        vm.warp(block.timestamp + 301);
        vault.applyMode(IVault.Mode.NORMAL, 2, "after cooldown");
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.NORMAL));
        
        vm.stopPrank();
    }
    
    // ============ Pausability Tests ============
    
    function testPauseUnpause() public {
        vm.prank(attacker);
        vm.expectRevert("VAULT: NOT_ADMIN");
        vault.pause();
        
        vm.startPrank(admin);
        vault.pause();
        
        // Operations should fail when paused
        vm.stopPrank();
        vm.prank(address(hook));
        vm.expectRevert("Pausable: paused");
        vault.applyMode(IVault.Mode.WIDENED, 1, "test");
        
        vm.prank(keeper);
        vm.expectRevert("Pausable: paused");
        vault.keeperRebalance(1e18, -1e18, "test");
        
        // Unpause and verify operations work
        vm.prank(admin);
        vault.unpause();
        
        vm.prank(address(hook));
        vault.applyMode(IVault.Mode.WIDENED, 1, "test");
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.WIDENED));
    }
    
    // ============ Delta Validation Tests ============
    
    function testInvalidDeltas() public {
        vm.startPrank(keeper);
        
        // Both deltas zero
        vm.expectRevert("VAULT: INVALID_DELTAS");
        vault.keeperRebalance(0, 0, "test");
        
        // Extremely large delta
        int256 tooLarge = 101_000_000 * 1e18;
        vm.expectRevert("VAULT: INVALID_DELTAS");
        vault.keeperRebalance(tooLarge, 0, "test");
        
        // Extremely negative delta
        vm.expectRevert("VAULT: INVALID_DELTAS");
        vault.keeperRebalance(0, -tooLarge, "test");
        
        vm.stopPrank();
    }
    
    function testValidDeltas() public {
        vm.startPrank(keeper);
        
        // Valid positive deltas
        vault.keeperRebalance(1e18, 1000e6, "add liquidity");
        
        // Valid negative deltas
        vault.keeperRebalance(-1e18, -1000e6, "remove liquidity");
        
        // Valid mixed deltas
        vault.keeperRebalance(1e18, -1000e6, "rebalance");
        
        vm.stopPrank();
    }
    
    // ============ Reason Validation Tests ============
    
    function testReasonLengthValidation() public {
        string memory longReason = "";
        for (uint i = 0; i < 30; i++) {
            longReason = string.concat(longReason, "0123456789");
        }
        
        vm.prank(address(hook));
        vm.expectRevert("VAULT: REASON_TOO_LONG");
        vault.applyMode(IVault.Mode.WIDENED, 1, longReason);
        
        vm.prank(keeper);
        vm.expectRevert("VAULT: REASON_TOO_LONG");
        vault.keeperRebalance(1e18, -1e18, longReason);
    }
    
    // ============ Re-entry Config Tests ============
    
    function testReentryConfigValidation() public {
        vm.startPrank(admin);
        
        // Cooldown too long
        vm.expectRevert("VAULT: COOLDOWN_TOO_LONG");
        vault.setReentryConfig(2 hours, 1e18, 5000, false);
        
        // Invalid BPS
        vm.expectRevert("VAULT: INVALID_BPS");
        vault.setReentryConfig(300, 1e18, 10001, false);
        
        // Valid config
        vault.setReentryConfig(600, 2e18, 9000, true);
        
        vm.stopPrank();
    }
}