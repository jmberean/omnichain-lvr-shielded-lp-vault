// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
contract LVRVault is Ownable {
    error OnlyHook();
    address public hook;
    address public keeper;
    event KeeperSet(address indexed keeper);
    event ModeChange(bytes32 indexed poolId, uint8 mode, uint64 epoch);
    event ModeApplied(bytes32 indexed poolId, uint8 mode, int24 lower, int24 upper, uint64 epoch);
    event LiquidityAction(address indexed keeper, int256 baseDelta, int256 quoteDelta, string memo);
    modifier onlyHook(){ if (msg.sender != hook) revert OnlyHook(); _; }
    constructor() Ownable(msg.sender) {}
    function setHook(address h) external onlyOwner {
        require(hook == address(0), "hook-already-set"); require(h != address(0), "hook=0"); hook = h;
    }
    function setKeeper(address k) external onlyOwner { keeper = k; emit KeeperSet(k); }
    function keeperRebalance(int256 base, int256 quote, string calldata memo) external {
        require(msg.sender == keeper, "not-keeper"); emit LiquidityAction(msg.sender, base, quote, memo);
    }
    function applyMode(bytes32 poolId, uint8 mode, uint64 epoch, int24 lowerTick, int24 upperTick) external onlyHook {
        emit ModeChange(poolId, mode, epoch); emit ModeApplied(poolId, mode, lowerTick, upperTick, epoch);
    }
}

contract Vault is LVRVault {
    constructor() LVRVault() {}
}
