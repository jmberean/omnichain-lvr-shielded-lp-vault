// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager as V4PoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {Vault} from "../contracts/Vault.sol";
import {LVRGuardV4Hook} from "../contracts/LVRGuardV4Hook.sol";

contract DeployLocal is Script {
    // Foundry's CREATE2 deployer
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        // For local smoke: allow override; use a non-zero placeholder otherwise
        address manager = vm.envOr("POOL_MANAGER", address(0x0000000000000000000000000000000000000001));

        Vault vault = new Vault(msg.sender);

        // afterSwap-only permission bit
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);

        LVRGuardV4Hook.Config memory cfg = LVRGuardV4Hook.Config({
            minFlipInterval: 60,
            dwellBlocks: 2,
            confirmBlocks: 2,
            homeWidthTicks: 120,
            recentreWidthMult: 3
        });

        (address pre, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            1_000_000, // attempt limit
            type(LVRGuardV4Hook).creationCode,
            abi.encode(V4PoolManager(manager), vault, cfg)
        );

        LVRGuardV4Hook hook = new LVRGuardV4Hook{salt: salt}(V4PoolManager(manager), vault, cfg);
        require(address(hook) == pre, "hook address mismatch");
        vault.setHook(address(hook));

        console2.log("Vault  :", address(vault));
        console2.log("Hook   :", address(hook));
        console2.log("Manager:", manager);

        vm.stopBroadcast();
    }
}
