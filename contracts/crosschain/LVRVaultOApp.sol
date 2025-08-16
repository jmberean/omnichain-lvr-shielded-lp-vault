// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// LayerZero v2 OApp
import {OApp} from "LayerZero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/OApp.sol";
import {Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroReceiver.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

/// @notice Minimal OApp wrapper (constructor forwards endpoint + owner).
contract LVRVaultOApp is OApp {
    /// @param endpoint LayerZero V2 Endpoint address for this chain
    /// @param owner    Initial owner (required by Ownable via OApp)
    constructor(address endpoint, address owner) OApp(endpoint, owner) {}

    /// @notice Example broadcast (you’ll replace with a typed Mode payload later)
    function broadcast(bytes32 topic, bytes calldata data, uint32 dstEid, bytes calldata options)
        external
        payable
    {
        _lzSend(dstEid, abi.encode(topic, data), options, MessagingFee(msg.value, 0), payable(msg.sender));
    }

    /// @dev Required receive hook (no-op for now)
    function _lzReceive(
        Origin calldata,   // src
        bytes32,           // guid
        bytes calldata,    // payload
        address,           // executor
        bytes calldata     // extra
    ) internal override {}
}
