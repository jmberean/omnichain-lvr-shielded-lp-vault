// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

interface IVault {
    function notifySignal(PoolId id, int24 tick, int24 bandLo, int24 bandHi, uint8 mode, uint64 epoch) external;
    function notifyMode(bytes32 idRaw, uint8 newMode, uint64 epoch) external;
    function notifyModeApplied(bytes32 idRaw, uint8 appliedMode, uint64 epoch) external;
}

contract Vault is Ownable, IVault {
    constructor(address _owner) Ownable(_owner) {}

    address public hook;
    address public keeper;

    event Signal(address indexed hook, bytes32 indexed poolId, int24 tick, int24 bandLo, int24 bandHi, uint8 mode, uint64 epoch);
    event ModeChange(bytes32 indexed poolId, uint8 newMode, uint64 epoch);
    event ModeApplied(bytes32 indexed poolId, uint8 appliedMode, uint64 epoch);
    event LiquidityAction(int256 baseDelta, int256 limitDelta, string reason);

    modifier onlyHook() { require(msg.sender == hook, "onlyHook"); _; }
    modifier onlyKeeper() { require(msg.sender == keeper, "onlyKeeper"); _; }

    function setHook(address _hook) external onlyOwner { require(_hook != address(0), "hook=0"); hook = _hook; }
    function setKeeper(address _k) external onlyOwner { keeper = _k; }

    function notifySignal(PoolId id, int24 tick, int24 bandLo, int24 bandHi, uint8 mode, uint64 epoch) external onlyHook {
        emit Signal(msg.sender, PoolId.unwrap(id), tick, bandLo, bandHi, mode, epoch);
    }
    function notifyMode(bytes32 idRaw, uint8 newMode, uint64 epoch) external onlyHook { emit ModeChange(idRaw, newMode, epoch); }
    function notifyModeApplied(bytes32 idRaw, uint8 appliedMode, uint64 epoch) external onlyHook { emit ModeApplied(idRaw, appliedMode, epoch); }

    function keeperRebalance(int256 baseDelta, int256 limitDelta, string calldata reason) external onlyKeeper {
        emit LiquidityAction(baseDelta, limitDelta, reason);
    }
}
