// script/RunDemo.s.sol
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";

contract RunDemo is Script {
    function run() external {
        uint256 pk = 0x9a12079cebb28de053f07d1e38687c278af265c4ab378de24cd2ef4119c69c51;
        
        vm.startBroadcast(pk);
        
        LVRShieldHook hook = LVRShieldHook(payable(0x20c519Cca0360468C0eCd7A74bEc12b9895C44c0));
        bytes32 poolIdRaw = 0x000000000000000000000000000000000000000000000000000000000000457f;
        
        console2.log("Triggering demo mode change...");
        hook.adminApplyModeForDemo(
            PoolId.wrap(poolIdRaw),
            IVault.Mode.WIDENED,
            uint64(2),
            "demo-volatility",
            int24(100),
            int24(200)
        );
        
        console2.log("Demo transaction sent!");
        
        vm.stopBroadcast();
    }
}