// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager as V4PoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {EwmaLib} from "./libraries/EwmaLib.sol";

interface IVault {
    function notifySignal(PoolId id, int24 tick, int24 bandLo, int24 bandHi, uint8 mode, uint64 epoch) external;
    function notifyMode(bytes32 idRaw, uint8 newMode, uint64 epoch) external;
    function notifyModeApplied(bytes32 idRaw, uint8 appliedMode, uint64 epoch) external;
}

contract LVRGuardV4Hook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for V4PoolManager;

    struct Config {
        uint64 minFlipInterval;   // seconds
        uint32 dwellBlocks;       // blocks
        uint32 confirmBlocks;     // blocks
        int24  homeWidthTicks;    // +/- around current
        int24  recentreWidthMult; // multiplier * tickSpacing
    }

    IVault public immutable vault;

    uint64 public immutable MIN_FLIP_INTERVAL;
    uint32 public immutable DWELL_BLOCKS;
    uint32 public immutable CONFIRM_BLOCKS;
    int24  public immutable HOME_WIDTH_TICKS;
    int24  public immutable RECENTER_WIDTH_MULT;

    mapping(PoolId => uint64) public lastFlipAt;     // timestamp
    mapping(PoolId => uint64) public lastSignalBlock; // block numbers

    event SignalEmitted(bytes32 indexed poolId, int24 tick, int24 bandLo, int24 bandHi, uint8 mode, uint64 epoch);

    constructor(V4PoolManager _poolManager, IVault _vault, Config memory _cfg) BaseHook(_poolManager) {
        require(address(_vault) != address(0), "vault=0");
        vault = _vault;

        MIN_FLIP_INTERVAL   = _cfg.minFlipInterval;
        DWELL_BLOCKS        = _cfg.dwellBlocks;
        CONFIRM_BLOCKS      = _cfg.confirmBlocks;
        HOME_WIDTH_TICKS    = _cfg.homeWidthTicks;
        RECENTER_WIDTH_MULT = _cfg.recentreWidthMult;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory p) {
        p.afterSwap = true; // only afterSwap
    }

    function _afterSwap(
    address, PoolKey calldata key, V4PoolManager.SwapParams calldata, BalanceDelta, bytes calldata
    ) internal override returns (bytes4, int128) {

        PoolId id = key.toId();

        // dwell / hysteresis: avoid thrashing
        if (block.number - lastSignalBlock[id] < DWELL_BLOCKS) {
            return (BaseHook.afterSwap.selector, 0);
        }
        lastSignalBlock[id] = uint64(block.number);

        // read tick via StateLibrary
        (, int24 tick,,) = poolManager.getSlot0(id);

        // HOME placement: +/- width around aligned tick
        int24 spacing = key.tickSpacing;
        int24 width = HOME_WIDTH_TICKS != 0 ? HOME_WIDTH_TICKS : spacing * RECENTER_WIDTH_MULT;
        int24 aligned = (tick / spacing) * spacing;
        int24 bandLo = aligned - width;
        int24 bandHi = aligned + width;

        uint64 epoch = uint64(block.timestamp / (MIN_FLIP_INTERVAL == 0 ? 1 : MIN_FLIP_INTERVAL));
        emit SignalEmitted(PoolId.unwrap(id), tick, bandLo, bandHi, 0 /*HOME*/, epoch);
        vault.notifySignal(id, tick, bandLo, bandHi, 0 /*HOME*/, epoch);

        return (BaseHook.afterSwap.selector, 0);
    }

    /// @notice view helper for tests/demo
    function previewBand(int24 tick, int24 tickSpacing) external view returns (int24 lo, int24 hi) {
        int24 width = HOME_WIDTH_TICKS != 0 ? HOME_WIDTH_TICKS : tickSpacing * RECENTER_WIDTH_MULT;
        int24 aligned = (tick / tickSpacing) * tickSpacing;
        lo = aligned - width;
        hi = aligned + width;
    }
}
