// script/DeployHookFinal.s.sol
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {IPriceOracle} from "../contracts/oracle/IPriceOracle.sol";
import {HookCreate2Factory} from "../contracts/utils/HookCreate2Factory.sol";
import {Vault} from "../contracts/Vault.sol";

contract DeployHookFinal is Script {
    function run() external {
        // Hardcode everything for reliability
        uint256 deployerPrivateKey = 0x9a12079cebb28de053f07d1e38687c278af265c4ab378de24cd2ef4119c69c51;
        address deployer = 0xC49DC7A54C3efd7FBF01d61dF1266C3BfCdF360a;
        
        address vault = 0x84a4871295867f587B15EAFF82e80eA2EbA79a6C;
        address oracle = 0xf406Cf48630FFc810FCBF1454d8F680a36D1AF64;
        address factory = 0x45ad11A2855e010cd57C8C8eF6fb5A15e15C6b7A;
        
        console2.log("Using contracts:");
        console2.log("Vault:", vault);
        console2.log("Oracle:", oracle);
        console2.log("Factory:", factory);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Use placeholder PoolManager (real one doesn't exist on Unichain Sepolia yet)
        IPoolManager manager = IPoolManager(address(0xFEE1));
        
        bytes memory ctorArgs = abi.encode(
            manager,
            IVault(vault),
            IPriceOracle(oracle),
            deployer
        );
        
        // Permission flags for LVR Shield Hook
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG |           // 0x0080
            Hooks.AFTER_SWAP_FLAG |            // 0x0040  
            Hooks.AFTER_ADD_LIQUIDITY_FLAG    // 0x0400
        ); // Total: 0x04C0
        
        console2.log("Mining salt for permission bits 0x04C0...");
        (address predicted, bytes32 salt) = HookMiner.find(
            factory,
            flags,
            type(LVRShieldHook).creationCode,
            ctorArgs
        );
        
        console2.log("Salt found:");
        console2.logBytes32(salt);
        console2.log("Predicted address:", predicted);
        
        // Deploy via CREATE2
        bytes memory initcode = abi.encodePacked(
            type(LVRShieldHook).creationCode,
            ctorArgs
        );
        
        console2.log("Deploying Hook via CREATE2...");
        address hook = HookCreate2Factory(factory).deploy(salt, initcode);
        require(hook == predicted, "Hook address mismatch");
        
        console2.log("Hook deployed:", hook);
        
        // Wire vault to hook
        console2.log("Wiring Vault to Hook...");
        Vault(vault).setHook(hook);
        
        // Configure with default LVR params
        console2.log("Setting LVR config...");
        LVRShieldHook(payable(hook)).setLVRConfig(100, 500, 300);
        
        console2.log("\n=== DEPLOYMENT COMPLETE ===");
        console2.log("Vault :", vault);
        console2.log("Hook  :", hook);
        console2.log("Oracle:", oracle);
        console2.log("Salt  :");
        console2.logBytes32(salt);
        console2.log("\nExport these:");
        console2.log(string.concat("export HOOK=", vm.toString(hook)));
        console2.log(string.concat("export DEMO_POOL_ID=", vm.toString(salt)));
        
        vm.stopBroadcast();
    }
}