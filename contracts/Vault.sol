// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IVault} from "./interfaces/IVault.sol";

contract Vault is IVault {
    bytes32 private _poolId;
    Mode    private _mode;
    uint64  private _epoch;

    address private _admin;
    address private _hook;
    address private _keeper;
    
    mapping(bytes32 => address) private _poolHooks;

    modifier onlyAdmin() {
        require(msg.sender == _admin, "NOT_ADMIN");
        _;
    }

    constructor(bytes32 poolId_) {
        _poolId = poolId_;
        _mode = Mode.NORMAL;
        _epoch = 0;
        _admin = msg.sender;
        emit AdminChanged(_admin);
    }

    function poolId() external view returns (bytes32) { return _poolId; }
    function currentMode() external view returns (Mode) { return _mode; }
    function modeEpoch() external view returns (uint64) { return _epoch; }

    function admin() external view returns (address) { return _admin; }
    function hook() external view returns (address) { return _hook; }
    function keeper() external view returns (address) { return _keeper; }

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
    
    // FIXED: Renamed parameter to avoid conflict with poolId() function
    function registerPoolHook(bytes32 poolId_, address hookAddr) external onlyAdmin {
        _poolHooks[poolId_] = hookAddr;
        emit PoolHookRegistered(poolId_, hookAddr);
    }

    function applyMode(Mode mode, uint64 epoch, string calldata reason) external {
        require(_poolHooks[_poolId] != address(0), "NO_HOOK_SET");
        require(msg.sender == _poolHooks[_poolId], "NOT_AUTHORIZED_HOOK");
        
        _mode = mode;
        _epoch = epoch;
        emit ModeApplied(_poolId, uint8(mode), epoch, reason);
        
        bool shouldReenter = _evaluateReentry(mode);
        emit ReentryDecision(_poolId, shouldReenter, uint8(mode));
    }
    
    function _evaluateReentry(Mode mode) private pure returns (bool) {
        return mode == Mode.NORMAL;
    }

    function keeperRebalance(int256 baseDelta, int256 quoteDelta, string calldata reason) external {
        require(msg.sender == _keeper, "NOT_KEEPER");
        emit LiquidityAction(_poolId, uint8(_mode), _epoch, baseDelta, quoteDelta, reason);
    }
}