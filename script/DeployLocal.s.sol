// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {Vault} from "../contracts/Vault.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";
import {HookCreate2Factory} from "../contracts/utils/HookCreate2Factory.sol";

contract DeployLocal is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk); // ✅ use EOA explicitly

        vm.startBroadcast(pk);

        // 1) Deploy Vault (admin = deployer) and CREATE2 factory
        Vault vault = new Vault(deployer);
        HookCreate2Factory factory = new HookCreate2Factory();

        // 2) Prepare Hook constructor args
        IPoolManager manager = IPoolManager(address(0xFEE1)); // placeholder for local
        bytes memory ctorArgs = abi.encode(manager, IVault(address(vault)), deployer);

        // 3) Mine salt for address-encoded permissions AGAINST the factory
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        (address predicted, bytes32 salt) =
            HookMiner.find(address(factory), flags, type(LVRShieldHook).creationCode, ctorArgs);

        // 4) CREATE2 deploy hook via factory
        bytes memory initcode = abi.encodePacked(type(LVRShieldHook).creationCode, ctorArgs);
        address hookAddr = factory.deploy(salt, initcode);
        require(hookAddr == predicted, "mined address mismatch");

        // 5) Wire Vault → Hook so onlyHook checks pass
        vault.setHook(hookAddr);

        console2.log("Vault  :", address(vault));
        console2.log("Hook   :", hookAddr);
        console2.logBytes32(salt);

        vm.stopBroadcast();
    }
}
