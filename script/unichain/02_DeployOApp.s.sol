// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {LVRVaultOApp} from "../../contracts/crosschain/LVRVaultOApp.sol";

contract DeployOApp is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address endpoint = vm.envAddress("LZ_ENDPOINT"); // set per-chain
        vm.startBroadcast(pk);
        LVRVaultOApp oapp = new LVRVaultOApp(endpoint, vm.addr(pk));
        vm.stopBroadcast();
        console2.log("OApp:", address(oapp));
    }
}
