// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Vault} from "../contracts/Vault.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";
import {HookCreate2Factory} from "../contracts/utils/HookCreate2Factory.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

contract DeployLocal is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        // 1) Deploy Vault and Factory on-chain
        vm.startBroadcast(pk);
        Vault vault = new Vault(deployer);
        HookCreate2Factory factory = new HookCreate2Factory();
        vm.stopBroadcast();

        // 2) Compute salt off-chain so predicted address ends with ...0000 (all-false perms)
        bytes memory initCode = abi.encodePacked(
            type(LVRShieldHook).creationCode,
            abi.encode(IPoolManager(address(0)), IVault(address(vault)), deployer)
        );
        bytes32 initHash = keccak256(initCode);

        bytes32 salt;
        address predicted;
        unchecked {
            for (uint256 i = 0;; ++i) {
                salt = bytes32(i);
                predicted = address(uint160(uint(keccak256(abi.encodePacked(
                    bytes1(0xff), address(factory), salt, initHash
                )))));
                if (uint16(uint160(predicted)) == 0) break; // ends with 0x0000
            }
        }

        // 3) Deploy Hook via CREATE2 and wire it
        vm.startBroadcast(pk);
        address hookAddr = factory.deploy(initCode, salt);
        require(hookAddr == predicted, "DEPLOY_ADDR_MISMATCH");
        LVRShieldHook hook = LVRShieldHook(hookAddr);

        vault.setHook(address(hook));

        bytes32 poolId = bytes32(uint256(0x1234));
        hook.adminApplyModeForDemo(poolId, IVault.Mode.NORMAL, 1, "bootstrap", 0, 0);
        vm.stopBroadcast();

        console2.log("Vault  :", address(vault));
        console2.log("Hook   :", address(hook));
        console2.log("Salt   :", uint256(salt));
    }
}
