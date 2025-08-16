// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IVault} from "./interfaces/IVault.sol";

contract Vault is IVault {
    bytes32 private _poolId;
    Mode private _mode;
    uint64 private _epoch;

    address private _admin;
    address private _hook;
    address private _keeper;

    modifier onlyAdmin() {
        require(msg.sender == _admin, "NOT_ADMIN");
        _;
    }

    modifier onlyHook() {
        require(msg.sender == _hook, "NOT_HOOK");
        _;
    }

    constructor(bytes32 poolId_) {
        _poolId = poolId_;
        _mode = Mode.NORMAL;
        _epoch = 0;
        _admin = msg.sender;
        emit AdminChanged(_admin);
    }

    function poolId() external view returns (bytes32) {
        return _poolId;
    }

    function currentMode() external view returns (Mode) {
        return _mode;
    }

    function modeEpoch() external view returns (uint64) {
        return _epoch;
    }

    function admin() external view returns (address) {
        return _admin;
    }

    function hook() external view returns (address) {
        return _hook;
    }

    function keeper() external view returns (address) {
        return _keeper;
    }

    function setAdmin(address admin_) external onlyAdmin {
        _admin = admin_;
        emit AdminChanged(admin_);
    }

    function setHook(address hook_) external onlyAdmin {
        _hook = hook_;
        emit HookChanged(hook_);
    }



    function setKeeper(address keeper_) external onlyAdmin {
        _keeper = keeper_;
        emit KeeperChanged(keeper_);
    }

    function applyMode(Mode mode, uint64 epoch, string calldata reason) external onlyHook {
        _mode = mode;
        _epoch = epoch;
        emit ModeApplied(_poolId, uint8(mode), epoch, reason);
    }

    function keeperRebalance(int256 baseDelta, int256 quoteDelta, string calldata reason) external {
        require(msg.sender == _keeper, "NOT_KEEPER");
        emit LiquidityAction(_poolId, uint8(_mode), _epoch, baseDelta, quoteDelta, reason);
    }
}