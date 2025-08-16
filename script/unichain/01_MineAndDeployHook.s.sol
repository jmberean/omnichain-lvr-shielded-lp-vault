// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IVault} from "../../contracts/interfaces/IVault.sol";
import {LVRShieldHook} from "../../contracts/hooks/v4/LVRShieldHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

contract MineAndDeployHook is Script {
    // TODO: fill with real PoolManager on Unichain Sepolia
    address constant UNICHAIN_SEPOLIA_POOL_MANAGER = address(0);

    function run() external {
        require(UNICHAIN_SEPOLIA_POOL_MANAGER != address(0), "SET_POOL_MANAGER");

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        require(vaultAddr != address(0), "SET_VAULT_ADDRESS");

        vm.startBroadcast(pk);

        // 3-arg ctor: (manager, vault, admin)
        LVRShieldHook hook = new LVRShieldHook(
            IPoolManager(UNICHAIN_SEPOLIA_POOL_MANAGER),
            IVault(vaultAddr),
            deployer
        );

        vm.stopBroadcast();
        console2.log("Hook deployed:", address(hook));
    }
}
