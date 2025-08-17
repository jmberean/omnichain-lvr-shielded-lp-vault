// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {Vault} from "../../contracts/Vault.sol";
import {IVault} from "../../contracts/interfaces/IVault.sol";
import {LVRShieldHook} from "../../contracts/hooks/v4/LVRShieldHook.sol";
import {HookCreate2Factory} from "../../contracts/utils/HookCreate2Factory.sol";

contract MineAndDeployHook is Script {
    // ✅ checksummed address (update if needed)
    address constant POOL_MANAGER_UNICHAIN_SEPOLIA = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk); // ✅ use EOA explicitly

        vm.startBroadcast(pk);

        Vault vault = new Vault(deployer);
        HookCreate2Factory factory = new HookCreate2Factory();

        bytes memory ctorArgs = abi.encode(IPoolManager(POOL_MANAGER_UNICHAIN_SEPOLIA), IVault(address(vault)), deployer);
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

        (address predicted, bytes32 salt) =
            HookMiner.find(address(factory), flags, type(LVRShieldHook).creationCode, ctorArgs);

        address hookAddr = factory.deploy(salt, abi.encodePacked(type(LVRShieldHook).creationCode, ctorArgs));
        require(hookAddr == predicted, "mined address mismatch");

        vault.setHook(hookAddr);

        console2.log("Vault  :", address(vault));
        console2.log("Hook   :", hookAddr);
        console2.logBytes32(salt);

        vm.stopBroadcast();
    }
}
