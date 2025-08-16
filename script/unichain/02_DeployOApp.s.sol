// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import "forge-std/Script.sol";
import {LVRVaultOApp} from "../../contracts/crosschain/LVRVaultOApp.sol";

contract DeployOApp is Script {
  function run() external {
    vm.startBroadcast();
    LVRVaultOApp oapp = new LVRVaultOApp(msg.sender);
    console2.log("LVRVaultOApp:", address(oapp));
    vm.stopBroadcast();
  }
}
