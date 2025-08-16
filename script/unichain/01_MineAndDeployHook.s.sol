// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {IVault} from "../../contracts/interfaces/IVault.sol";
import {LVRShieldHook} from "../../contracts/hooks/v4/LVRShieldHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
// import {HookMiner} from "your/path/HookMiner.sol";

contract MineAndDeployHook is Script {
    address constant UNICHAIN_SEPOLIA_POOL_MANAGER = address(0); // <- FILL ME

    function run() external {
        require(UNICHAIN_SEPOLIA_POOL_MANAGER != address(0), "SET_POOL_MANAGER");

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        require(vaultAddr != address(0), "SET_VAULT_ADDRESS");

        vm.startBroadcast(pk);

        LVRShieldHook hook = new LVRShieldHook(
            IPoolManager(UNICHAIN_SEPOLIA_POOL_MANAGER),
            IVault(vaultAddr),
            deployer
        );

        vm.stopBroadcast();

        console2.log("Hook deployed:", address(hook));
    }
}
