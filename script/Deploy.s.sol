// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {HookMiner} from "v4-periphery/utils/HookMiner.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Vault} from "../contracts/Vault.sol";
import {LVRGuardV4Hook} from "../contracts/hooks/LVRGuardV4Hook.sol";
import {MockPriceOracle} from "../contracts/mocks/MockPriceOracle.sol";

contract Deploy is Script {
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920ca78fbf26c0b4956c;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address poolManagerAddress = vm.envAddress("POOL_MANAGER");

        vm.startBroadcast(deployerPrivateKey);

        Vault vault = new Vault(bytes32("POOL"));
        MockPriceOracle oracle = new MockPriceOracle();

        uint160 flags = Hooks.AFTER_SWAP_FLAG;

        bytes memory constructorArgs = abi.encode(
            IPoolManager(poolManagerAddress),
            vault,
            oracle
        );

        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(LVRGuardV4Hook).creationCode,
            constructorArgs
        );

        LVRGuardV4Hook hook = new LVRGuardV4Hook{salt: salt}(
            IPoolManager(poolManagerAddress),
            vault,
            oracle
        );
        require(address(hook) == hookAddress, "Deploy: hook address mismatch");

        vault.setHook(address(hook));

        console.log("Vault   :", address(vault));
        console.log("Oracle  :", address(oracle));
        console.log("Hook    :", address(hook));

        vm.stopBroadcast();
    }
}