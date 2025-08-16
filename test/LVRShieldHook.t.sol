// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../contracts/Vault.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {IPriceOracle} from "../contracts/oracle/IPriceOracle.sol";
import {MockPriceOracle} from "../contracts/mocks/MockPriceOracle.sol";
import {LVRShieldHook} from "../contracts/hooks/LVRShieldHook.sol";

contract LVRShieldHookTest is Test {
    Vault vault;
    MockPriceOracle oracle;
    LVRShieldHook hook;
    bytes32 constant POOL_ID = bytes32("POOL");

    function setUp() public {
        vault = new Vault(POOL_ID);
        oracle = new MockPriceOracle();
        hook = new LVRShieldHook(POOL_ID, IPriceOracle(address(oracle)), IVault(address(vault)));
    }

    function testWidenWithHighRiskOff() public {
        // disable risk-off by setting very high threshold
        hook.setConfig(100, 10_000, 300);

        oracle.setPrice(POOL_ID, 1000e18);
        hook.check(uint64(1)); // init
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.NORMAL));

        oracle.setPrice(POOL_ID, 1150e18); // ~12.6% move -> wider than 1% -> WIDENED (risk-off disabled)
        hook.check(uint64(2));
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.WIDENED));
    }

    function testRiskOffDefault() public {
        // defaults: widen=1%, riskOff=5%
        oracle.setPrice(POOL_ID, 1000e18);
        hook.check(uint64(10)); // init
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.NORMAL));

        oracle.setPrice(POOL_ID, 1200e18); // 20% -> risk-off
        hook.check(uint64(11));
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.RISK_OFF));
    }

    function testStalenessBlocksChanges() public {
        hook.setConfig(100, 500, 1); // 1s stale window
        oracle.setPrice(POOL_ID, 1000e18);
        hook.check(uint64(20));
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.NORMAL));

        // set fresh price
        oracle.setPrice(POOL_ID, 2000e18);

        // make it stale before calling check
        vm.warp(block.timestamp + 400);
        hook.check(uint64(21));
        // no change because price read is stale relative to now
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.NORMAL));
    }
}
