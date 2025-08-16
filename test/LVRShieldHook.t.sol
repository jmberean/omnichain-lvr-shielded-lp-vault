// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../contracts/Vault.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {IPriceOracle} from "../contracts/oracle/IPriceOracle.sol";
import {MockPriceOracle} from "../contracts/mocks/MockPriceOracle.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";

contract LVRShieldHookTest is Test {
    Vault vault;
    MockPriceOracle oracle;
    LVRShieldHook hook;
    bytes32 constant POOL_ID = bytes32("POOL");

    function setUp() public {
        vault = new Vault(POOL_ID);
        oracle = new MockPriceOracle();
        hook = new LVRShieldHook(POOL_ID, IPriceOracle(address(oracle)), IVault(address(vault)));
        vault.setHook(address(hook));
    }

    function testWidenWithHighRiskOff() public {
        hook.setConfig(100, 10_000, 300);
        oracle.setPrice(POOL_ID, 1000e18);
        hook.check(uint64(1));
        oracle.setPrice(POOL_ID, 1150e18);
        hook.check(uint64(2));
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.WIDENED));
    }

    function testRiskOffDefault() public {
        oracle.setPrice(POOL_ID, 1000e18);
        hook.check(uint64(10));
        oracle.setPrice(POOL_ID, 1200e18);
        hook.check(uint64(11));
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.RISK_OFF));
    }

    function testStalenessBlocksChanges() public {
        hook.setConfig(100, 500, 1);
        oracle.setPrice(POOL_ID, 1000e18);
        hook.check(uint64(20));
        oracle.setPrice(POOL_ID, 2000e18);
        vm.warp(block.timestamp + 400);
        hook.check(uint64(21));
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.NORMAL));
    }
}
