// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {Vault} from "../contracts/Vault.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {IPriceOracle} from "../contracts/oracle/IPriceOracle.sol";
import {MockPriceOracle} from "../contracts/mocks/MockPriceOracle.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";

contract DeployLocal is Script {
    bytes32 constant POOL_ID = bytes32("POOL");

    function run() external {
        vm.startBroadcast();

        Vault vault = new Vault(POOL_ID);
        MockPriceOracle oracle = new MockPriceOracle();
        LVRShieldHook hook = new LVRShieldHook(
            POOL_ID,
            IPriceOracle(address(oracle)),
            IVault(address(vault))
        );

        vault.setHook(address(hook));

        oracle.setPrice(POOL_ID, 1000e18);
        hook.check(100, 1);

        console.log("Vault   :", address(vault));
        console.log("Oracle  :", address(oracle));
        console.log("Hook    :", address(hook));

        vm.stopBroadcast();
    }
}
