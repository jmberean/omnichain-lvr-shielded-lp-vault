// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {Vault} from "../contracts/Vault.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";
import {MockPriceOracle} from "../contracts/oracle/MockPriceOracle.sol";
import {HookCreate2Factory} from "../contracts/utils/HookCreate2Factory.sol";

contract DeployUnichain is Script {
    // Unichain Sepolia PoolManager (update if changed)
    address constant POOL_MANAGER = 0x5F96F76c945642E0B8F33270754d1c3450f9d81D;
    
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        
        vm.startBroadcast(pk);
        
        // 1. Deploy core contracts
        Vault vault = new Vault(deployer);
        MockPriceOracle oracle = new MockPriceOracle(deployer);
        HookCreate2Factory factory = new HookCreate2Factory();
        
        // 2. Prepare hook constructor args
        bytes memory ctorArgs = abi.encode(
            IPoolManager(POOL_MANAGER),
            IVault(address(vault)),
            oracle,
            deployer
        );
        
        // 3. Mine salt for correct permission bits
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.AFTER_ADD_LIQUIDITY_FLAG
        );
        
        (address predicted, bytes32 salt) = HookMiner.find(
            address(factory),
            flags,
            type(LVRShieldHook).creationCode,
            ctorArgs
        );
        
        // 4. Deploy hook via CREATE2
        bytes memory initcode = abi.encodePacked(
            type(LVRShieldHook).creationCode,
            ctorArgs
        );
        address hookAddr = factory.deploy(salt, initcode);
        require(hookAddr == predicted, "address mismatch");
        
        // 5. Wire vault to hook
        vault.setHook(hookAddr);
        vault.setKeeper(deployer); // Deployer as keeper for demo
        
        // 6. Configure hook with default params
        LVRShieldHook(hookAddr).setLVRConfig(100, 500, 300);
        
        console2.log("=== Unichain Deployment ===");
        console2.log("Vault   :", address(vault));
        console2.log("Hook    :", hookAddr);
        console2.log("Oracle  :", address(oracle));
        console2.log("Factory :", address(factory));
        console2.logBytes32(salt);
        
        vm.stopBroadcast();
    }
}