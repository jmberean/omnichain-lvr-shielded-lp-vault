// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LVRGuardVault} from "../contracts/LVRGuardVault.sol";
import {LVRGuardV4Hook} from "../contracts/LVRGuardV4Hook.sol";

import {HookMiner} from "v4-periphery/utils/HookMiner.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

contract DeployLocal is Script {
    function run() external returns (address hookAddress, address vaultAddress) {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployer);

        // 1. Deploy the Vault
        LVRGuardVault vault = new LVRGuardVault();
        vaultAddress = address(vault);
        console.log("Vault deployed to:", vaultAddress);

        // 2. Prepare for Hook deployment
        bytes memory creationCode = abi.encodePacked(
            type(LVRGuardV4Hook).creationCode,
            abi.encode(vault)
        );
        uint16 flags = Hooks.AFTER_SWAP_FLAG;

        // 3. Find the salt that gives the desired permission bits in the address
        (address predictedAddress, bytes32 salt) = HookMiner.find(deployer, flags, keccak256(creationCode), bytes32(0));

        // 4. Deploy the hook using CREATE2 with the found salt
        LVRGuardV4Hook hook = new LVRGuardV4Hook{salt: salt}(vault);
        hookAddress = address(hook);

        vm.stopBroadcast();

        // 5. Verification
        console.log("Deployer:", deployer);
        console.log("Salt used:", salt);
        console.log("Predicted Hook Address:", predictedAddress);
        console.log("Actual Hook Address:  ", hookAddress);
        require(hookAddress == predictedAddress, "Deployment address mismatch");
        require(uint16(bytes2(bytes20(hookAddress))) == flags, "Permission bits mismatch");
    }
}