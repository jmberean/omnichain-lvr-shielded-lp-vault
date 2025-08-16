// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";

contract EmitDemo is Script {
    function run() external {
        IVault vault = IVault(vm.envAddress("VAULT"));
        LVRShieldHook hook = LVRShieldHook(vm.envAddress("HOOK"));

        vm.startBroadcast();
        hook.poke();
        vault.keeperRebalance(int256(1e18), int256(-3e18), "demo");
        vm.stopBroadcast();
    }
}
