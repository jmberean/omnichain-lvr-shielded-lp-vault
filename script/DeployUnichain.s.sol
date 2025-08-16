// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Vault} from "../contracts/Vault.sol";
import {LVRGuardV4Hook} from "../contracts/hooks/LVRGuardV4Hook.sol";

contract DeployUnichain is Script {
    address constant POOL_MANAGER = 0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A;
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        
        // Check if we have a mined salt
        bytes32 salt;
        try vm.envBytes32("HOOK_SALT") returns (bytes32 s) {
            salt = s;
        } catch {
            console2.log("No HOOK_SALT found, deploying without specific address");
            salt = bytes32(0);
        }
        
        vm.startBroadcast(deployerKey);
        
        // Deploy Vault
        bytes32 poolId = keccak256("WETH-USDC-3000");
        Vault vault = new Vault(poolId);
        console2.log("Vault deployed:", address(vault));
        
        // Deploy Hook
        LVRGuardV4Hook hook;
        if (salt != bytes32(0)) {
            hook = new LVRGuardV4Hook{salt: salt}(
                IPoolManager(POOL_MANAGER),
                vault
            );
        } else {
            hook = new LVRGuardV4Hook(
                IPoolManager(POOL_MANAGER),
                vault
            );
        }
        console2.log("Hook deployed:", address(hook));
        
        // Verify hook permissions if salt was used
        if (salt != bytes32(0)) {
            uint160 hookFlags = uint160(uint256(uint160(address(hook))));
            require(
                hookFlags & Hooks.AFTER_SWAP_FLAG == Hooks.AFTER_SWAP_FLAG,
                "Hook address does not have afterSwap permission"
            );
            console2.log("Hook permissions verified!");
        }
        
        // Configure vault
        vault.registerPoolHook(poolId, address(hook));
        vault.setKeeper(msg.sender);
        
        vm.stopBroadcast();
        
        console2.log("\n=== Deployment Complete ===");
        console2.log("Network: Unichain Sepolia (1301)");
        console2.log("Vault:", address(vault));
        console2.log("Hook:", address(hook));
        console2.log("Pool ID:", vm.toString(poolId));
    }
}