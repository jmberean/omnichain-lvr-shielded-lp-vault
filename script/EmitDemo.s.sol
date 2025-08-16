// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";

contract EmitDemo is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        address hookAddr = vm.envAddress("HOOK_ADDRESS");
        LVRShieldHook hook = LVRShieldHook(hookAddr);

        // Emit a demo ModeApplied via the hook's admin helper (no old `poke()` anymore)
        bytes32 poolId = bytes32(uint256(0x1234));
        hook.adminApplyModeForDemo(poolId, IVault.Mode.WIDENED, 2, "demo", 0, 0);

        vm.stopBroadcast();
    }
}
