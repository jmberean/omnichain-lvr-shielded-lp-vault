// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {LVRVaultOApp} from "../../contracts/crosschain/LVRVaultOApp.sol";

/// @notice Example peer wiring script (works with the stub; swap to real OApp later)
contract SetPeers is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        address thisOApp = vm.envAddress("THIS_OAPP");   // deployed OApp on this chain
        address otherOApp = vm.envAddress("OTHER_OAPP"); // deployed OApp on the other chain
        uint32 peerEid = uint32(vm.envUint("PEER_EID")); // LayerZero EID for the other chain

        LVRVaultOApp oapp = LVRVaultOApp(thisOApp);
        // In real OApp you'd pass the remote address bytes; here we just pack to bytes32 for the stub.
        oapp.setPeer(peerEid, bytes32(uint256(uint160(otherOApp))));

        vm.stopBroadcast();
        console.log("peer set");
    }
}
