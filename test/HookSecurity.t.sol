// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LVRGuardV4Hook} from "../contracts/hooks/LVRGuardV4Hook.sol";
import {Vault} from "../contracts/Vault.sol";
import {MockPriceOracle} from "../contracts/mocks/MockPriceOracle.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

contract HookSecurityTest is Test {
    LVRGuardV4Hook hook;
    Vault vault;
    MockPriceOracle oracle;
    IPoolManager poolManager;
    
    address admin = address(0x1);
    address attacker = address(0x666);
    
    function setUp() public {
        vm.startPrank(admin);
        vault = new Vault(bytes32("TEST"));
        oracle = new MockPriceOracle();
        poolManager = IPoolManager(address(new MockPoolManager()));
        hook = new LVRGuardV4Hook(poolManager, vault, oracle);
        vault.setHook(address(hook));
        vm.stopPrank();
    }
    
    function testOnlyAdminCanSetConfig() public {
        vm.prank(attacker);
        vm.expectRevert(LVRGuardV4Hook.UnauthorizedCaller.selector);
        hook.setConfig(200, 600, 400);
        
        vm.prank(admin);
        hook.setConfig(200, 600, 400);
    }
    
    function testConfigValidation() public {
        vm.startPrank(admin);
        
        // widenBps >= riskOffBps
        vm.expectRevert(LVRGuardV4Hook.InvalidConfig.selector);
        hook.setConfig(500, 500, 300);
        
        // riskOffBps >= MAX_BPS
        vm.expectRevert(LVRGuardV4Hook.InvalidConfig.selector);
        hook.setConfig(100, 10001, 300);
        
        // staleAfter too short
        vm.expectRevert(LVRGuardV4Hook.InvalidConfig.selector);
        hook.setConfig(100, 500, 29);
        
        // staleAfter too long
        vm.expectRevert(LVRGuardV4Hook.InvalidConfig.selector);
        hook.setConfig(100, 500, 3601);
        
        vm.stopPrank();
    }
    
    function testOracleFailureHandling() public {
        // Set oracle to return 0 (simulating failure)
        oracle.setPrice(bytes32("TEST"), 0);
        
        // Hook should handle gracefully without reverting
        // This would be tested in integration with actual swaps
    }
}

// Mock Pool Manager for testing
contract MockPoolManager {
    function unlock(bytes calldata) external pure returns (bytes memory) {
        return "";
    }
    
    function getPool(bytes32) external pure returns (bytes memory) {
        return "";
    }
    
    function initialize(PoolKey calldata, uint160, bytes calldata) external pure {
        // Mock implementation
    }
}