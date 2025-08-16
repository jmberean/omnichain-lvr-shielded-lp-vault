// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IVault} from "./interfaces/IVault.sol";

contract Vault is IVault {
    bytes32 private _poolId;
    Mode    private _mode;
    uint64  private _epoch;

    constructor(bytes32 poolId_) {
        _poolId = poolId_;
        _mode = Mode.NORMAL;
        _epoch = 0;
    }

    function poolId() external view returns (bytes32) { return _poolId; }
    function currentMode() external view returns (Mode) { return _mode; }
    function modeEpoch() external view returns (uint64) { return _epoch; }

    function applyMode(Mode mode, uint64 epoch, string calldata reason) external {
        _mode = mode;
        _epoch = epoch;
        emit ModeApplied(_poolId, uint8(mode), epoch, reason);
    }

    function keeperRebalance(int256 baseDelta, int256 quoteDelta, string calldata reason) external {
        emit LiquidityAction(_poolId, uint8(_mode), _epoch, baseDelta, quoteDelta, reason);
    }
}
