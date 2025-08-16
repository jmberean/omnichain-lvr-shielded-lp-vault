// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OApp, Origin, MessagingFee} from "lz/oapp/OApp.sol"; // remapped to .../contracts/oapp/OApp.sol

contract LVRVaultOApp is OApp {
  // From your spec (single endpoint across chains)
  address constant LZ_V2_ENDPOINT = 0x1a44076050125825900e736c501f859c50fe728c;

  constructor(address owner_) OApp(LZ_V2_ENDPOINT, owner_) {}

  function sendCrossChainMessage(uint32 dstEid, bytes memory message) external payable {
    // 50k gas options (can be replaced with OptionsBuilder later)
    bytes memory options = hex"0003010011010000000000000000000000000000c350";
    _lzSend(
      dstEid,
      abi.encode(message),
      options,
      MessagingFee(msg.value, 0),
      payable(msg.sender)
    );
  }

  function _lzReceive(
    Origin calldata, bytes32, bytes calldata payload, address, bytes calldata
  ) internal override {
    _processLVRSignal(payload);
  }

  function _processLVRSignal(bytes calldata /*payload*/) internal {
    // TODO: route to Vault/Hook (decode your struct and call into Vault)
  }
}
