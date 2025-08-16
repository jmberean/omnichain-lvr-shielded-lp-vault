// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {LVRGuardV4Hook} from "../contracts/hooks/LVRGuardV4Hook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";

contract MineHookAddress is Script {
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    function run() external {
        // Target flags for afterSwap only
        uint160 targetFlags = uint160(Hooks.AFTER_SWAP_FLAG);
        
        // Constructor arguments for the hook
        address poolManagerAddress = 0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A;
        address vaultPlaceholder = address(0x1234567890123456789012345678901234567890);
        
        bytes memory constructorArgs = abi.encode(
            poolManagerAddress,
            vaultPlaceholder
        );
        
        // Get creation code
        bytes memory creationCode = type(LVRGuardV4Hook).creationCode;
        
        // HookMiner.find expects 4 arguments: deployer, flags, creationCode, constructorArgs
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            targetFlags,
            creationCode,
            constructorArgs
        );
        
        console2.log("Found hook address:", hookAddress);
        console2.log("Salt:", vm.toString(salt));
        console2.log("\nAdd to .env:");
        console2.log("HOOK_SALT=", vm.toString(salt));
        console2.log("HOOK_ADDRESS=", hookAddress);
    }
}