// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import "forge-std/Script.sol";
import {LVRVaultOApp} from "../../contracts/crosschain/LVRVaultOApp.sol";

contract SetPeers is Script {
  // EIDs from your spec
  uint32 constant UNICHAIN_EID = 30320;
  uint32 constant ETHEREUM_EID = 30101;
  uint32 constant BASE_EID     = 30184;

  function run() external {
    address oappOnThisChain = vm.envAddress("THIS_OAPP");
    address oappOnOther     = vm.envAddress("PEER_OAPP");
    uint32  peerEid         = uint32(vm.envUint("PEER_EID")); // 30101 or 30184 or 30320

    vm.startBroadcast();
    LVRVaultOApp(oappOnThisChain).setPeer(peerEid, bytes32(uint256(uint160(oappOnOther))));
    console2.log("Peer set:", oappOnThisChain, "<->", oappOnOther, "eid", peerEid);
    vm.stopBroadcast();
  }
}
