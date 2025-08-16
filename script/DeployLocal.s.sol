// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

import {Vault} from "../contracts/Vault.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

contract DeployLocal is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        Vault vault = new Vault(deployer);
        // Local/demo: use a zero address for manager; on-chain you must pass the real PoolManager.
        LVRShieldHook hook = new LVRShieldHook(
            IPoolManager(address(0)),
            IVault(address(vault)),
            deployer
        );

        vault.setHook(address(hook));

        // Demo signal
        bytes32 poolId = bytes32(uint256(0x1234));
        hook.adminApplyModeForDemo(poolId, IVault.Mode.NORMAL, 1, "bootstrap", 0, 0);

        vm.stopBroadcast();

        console2.log("Vault  :", address(vault));
        console2.log("Hook   :", address(hook));
    }
}
