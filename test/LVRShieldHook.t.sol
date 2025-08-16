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

    function testThresholdLogic() public {
        oracle.setPrice(POOL_ID, 1000e18);
        hook.check(100, 1); // initialize baseline
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.NORMAL));

        oracle.setPrice(POOL_ID, 1005e18); // +0.5%
        hook.check(100, 2);
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.NORMAL));

        oracle.setPrice(POOL_ID, 1150e18); // ~12.6% move
        hook.check(100, 3);
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.WIDENED));
    }
}
