// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import "forge-std/Script.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {LVRShieldHook} from "../../contracts/hooks/v4/LVRShieldHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HookFlags} from "../../contracts/hooks/v4/utils/HookFlags.sol";

interface ICreate2Deployer {
  function deploy(bytes memory initCode, bytes32 salt) external payable returns (address addr);
}

contract MineAndDeployHook is Script {
  // from your spec (confirm if they change later)
  address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
  address constant UNICHAIN_SEPOLIA_POOL_MANAGER = 0x00b036b58a818b1bc34d502d3fe730db729e62ac;

  function run() external {
    vm.startBroadcast();

    bytes memory ctorArgs = abi.encode(IPoolManager(UNICHAIN_SEPOLIA_POOL_MANAGER));
    (address predicted, bytes32 salt) = HookMiner.find(
      CREATE2_DEPLOYER,
      HookFlags.FLAGS,
      type(LVRShieldHook).creationCode,
      ctorArgs
    );

    bytes memory initCode = abi.encodePacked(type(LVRShieldHook).creationCode, ctorArgs);
    address deployed = ICreate2Deployer(CREATE2_DEPLOYER).deploy(initCode, salt);
    require(deployed == predicted, "hook address mismatch");

    console2.log("LVRShieldHook (predicted):", predicted);
    console2.log("LVRShieldHook (deployed): ", deployed);

    vm.stopBroadcast();
  }
}
