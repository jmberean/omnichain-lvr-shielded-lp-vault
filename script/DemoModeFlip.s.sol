// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

import {IVault} from "../contracts/interfaces/IVault.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";

contract DemoModeFlip is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        
        // Read deployed addresses from env
        address hookAddr = vm.envAddress("DEMO_HOOK");
        bytes32 poolIdRaw = vm.envBytes32("DEMO_POOL_ID");
        
        vm.startBroadcast(pk);
        
        LVRShieldHook hook = LVRShieldHook(payable(hookAddr));
        PoolId poolId = PoolId.wrap(poolIdRaw);
        
        // Simulate mode transitions
        console2.log("Flipping to WIDENED mode...");
        hook.adminApplyModeForDemo(
            poolId,
            IVault.Mode.WIDENED,
            2,
            "demo-volatility",
            100,
            200
        );
        
        console2.log("Flipping to RISK_OFF mode...");
        hook.adminApplyModeForDemo(
            poolId,
            IVault.Mode.RISK_OFF,
            3,
            "demo-risk",
            0,
            500
        );
        
        console2.log("Returning to NORMAL mode...");
        hook.adminApplyModeForDemo(
            poolId,
            IVault.Mode.NORMAL,
            4,
            "demo-recovery",
            50,
            100
        );
        
        vm.stopBroadcast();
    }
}