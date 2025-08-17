// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

import {IVault} from "../contracts/interfaces/IVault.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";

contract SimulatePriceMove is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        LVRShieldHook hook = LVRShieldHook(payable(vm.envAddress("SIM_HOOK")));
        bytes32 poolIdRaw = vm.envBytes32("SIM_POOL_ID");

        hook.adminApplyModeForDemo(
            PoolId.wrap(poolIdRaw),
            IVault.Mode.WIDENED,
            uint64(42),
            "sim",
            int24(0),
            int24(0)
        );

        vm.stopBroadcast();
    }
}
