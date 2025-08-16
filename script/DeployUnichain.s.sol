// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Script.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {LVRGuardV4Hook} from "../contracts/LVRGuardV4Hook.sol";
import {Vault as LVRVault} from "../contracts/Vault.sol";

contract DeployUnichain is Script {
    function run() external {
        address pm = vm.envAddress("POOL_MANAGER");
        address owner = vm.envOr("OWNER", address(0));
        LVRGuardV4Hook.Config memory cfg = LVRGuardV4Hook.Config({
            ewmaAlphaPPM: 200_000, kSigma: 3, dwellSec: 120, minFlipIntervalSec: 60, homeTtlSec: 3600, recenterWidthMult: 50
        });
        vm.startBroadcast();
        LVRVault vault = new LVRVault();
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        bytes memory ctor = abi.encode(IPoolManager(pm), vault, cfg);
        (address mined, bytes32 salt) = HookMiner.find(address(this), flags, type(LVRGuardV4Hook).creationCode, ctor);
        LVRGuardV4Hook hook = new LVRGuardV4Hook{salt: salt}(IPoolManager(pm), vault, cfg);
        require(address(hook) == mined, "hook addr mismatch");
        vault.setHook(address(hook));
        if (owner != address(0)) { vault.transferOwnership(owner); }
        vm.stopBroadcast();
        string memory out = string.concat(
            "{\n  \"poolManager\":\"", vm.toString(pm),
            "\",\n  \"vault\":\"", vm.toString(address(vault)),
            "\",\n  \"hook\":\"", vm.toString(address(hook)), "\"\n}\n");
        vm.writeJson(out, "generated/addresses.unichain.json");
        console2.log("POOL_MANAGER:", pm); console2.log("VAULT:", address(vault)); console2.log("HOOK:", address(hook));
    }
}


