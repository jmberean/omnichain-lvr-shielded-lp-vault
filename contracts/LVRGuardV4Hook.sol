// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {EwmaLib} from "./libraries/EwmaLib.sol";

interface IVault {
    function applyMode(bytes32 poolId, uint8 mode, uint64 epoch, int24 lowerTick, int24 upperTick) external;
}

contract LVRGuardV4Hook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    enum Mode { NORMAL, RISK_OFF }
    struct Config {
        uint32 ewmaAlphaPPM;
        uint16 kSigma;
        uint32 dwellSec;
        uint32 minFlipIntervalSec;
        uint32 homeTtlSec;
        uint16 recenterWidthMult;
    }
    struct HomeSnapshot { int24 lower; int24 upper; uint64 ts; }
    struct PoolData {
        bool inRiskOff; uint64 epoch; uint64 lastFlipTs;
        int24 lastTick; uint32 sigmaTicks; HomeSnapshot home;
    }

    event HomeRecorded(bytes32 indexed poolId, int24 lower, int24 upper, uint64 ts, uint64 epoch);
    event ReentryDecision(bytes32 indexed poolId, bool choseHome, int24 currTick, int24 homeMid,
        uint24 sigmaTicks, uint16 kSigma, bool homeExpired, uint64 epoch);
    event Signal(bytes32 indexed poolId, int24 currTick, uint24 sigmaTicks, uint64 ts);
    event ModeChange(bytes32 indexed poolId, uint8 mode, uint64 epoch);
    event ModeApplied(bytes32 indexed poolId, uint8 mode, int24 lower, int24 upper, uint64 epoch);

    IVault public immutable vault;
    Config public immutable cfg;
    mapping(PoolId => PoolData) public pools;

    constructor(IPoolManager _poolManager, IVault _vault, Config memory _cfg) BaseHook(_poolManager) {
        require(address(_vault) != address(0), "vault=0");
        require(_cfg.ewmaAlphaPPM > 0 && _cfg.ewmaAlphaPPM <= 1_000_000, "alpha");
        require(_cfg.kSigma >= 1, "k");
        require(_cfg.recenterWidthMult >= 8, "width");
        vault = _vault; cfg = _cfg;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory p) {
        p.afterSwap = true;
        p.beforeSwapReturnDelta = false; p.afterSwapReturnDelta = false;
        p.afterAddLiquidityReturnDelta = false; p.afterRemoveLiquidityReturnDelta = false;
    }

    function recordHomeAndExit(PoolKey calldata key, int24 lower, int24 upper) external {
        _recordHomeAndExitInternal(key.toId(), lower, upper);
    }
    function recordHomeAndExitRaw(bytes32 poolId, int24 lower, int24 upper) external {
        _recordHomeAndExitInternal(PoolId.wrap(poolId), lower, upper);
    }
    function _recordHomeAndExitInternal(PoolId id, int24 lower, int24 upper) internal {
        PoolData storage d = pools[id];
        d.home = HomeSnapshot({lower: lower, upper: upper, ts: uint64(block.timestamp)});
        d.inRiskOff = true; d.lastFlipTs = uint64(block.timestamp); d.epoch += 1;
        emit HomeRecorded(PoolId.unwrap(id), lower, upper, d.home.ts, d.epoch);
        emit ModeChange(PoolId.unwrap(id), uint8(Mode.RISK_OFF), d.epoch);
    }

    function _afterSwap(
        address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata
    ) internal override returns (bytes4, int128) {
        PoolId id = key.toId(); PoolData storage d = pools[id];
        (, int24 tick,,) = poolManager.getSlot0(id);
        uint256 sample = d.lastTick == 0 ? 0 : EwmaLib.absDiff(tick, d.lastTick);
        uint32 sigma = uint32(EwmaLib.update(d.sigmaTicks, sample, cfg.ewmaAlphaPPM));
        d.sigmaTicks = sigma; d.lastTick = tick;
        emit Signal(PoolId.unwrap(id), tick, sigma, uint64(block.timestamp));

        if (d.inRiskOff) {
            bool dwellOk = block.timestamp >= d.lastFlipTs + cfg.dwellSec;
            bool flipOk  = block.timestamp >= d.lastFlipTs + cfg.minFlipIntervalSec;
            bool homeExpired = block.timestamp >= uint256(d.home.ts) + cfg.homeTtlSec;
            if (dwellOk && flipOk) {
                int24 midHome = (d.home.lower + d.home.upper) / 2;
                uint256 dist = EwmaLib.absDiff(tick, midHome);
                bool useHome = !homeExpired && dist <= uint256(cfg.kSigma) * uint256(sigma);
                int24 lower; int24 upper;
                if (useHome) { lower = d.home.lower; upper = d.home.upper; }
                else {
                    int24 s = key.tickSpacing; int24 snapped = tick - (tick % s);
                    int24 half = int24(int256(uint256(cfg.recenterWidthMult) * uint256(uint24(s))));
                    lower = snapped - half; upper = snapped + half;
                }
                d.inRiskOff = false; d.lastFlipTs = uint64(block.timestamp); d.epoch += 1;
                emit ReentryDecision(PoolId.unwrap(id), useHome, tick, midHome, sigma, cfg.kSigma, homeExpired, d.epoch);
                emit ModeChange(PoolId.unwrap(id), uint8(Mode.NORMAL), d.epoch);
                vault.applyMode(PoolId.unwrap(id), uint8(Mode.NORMAL), d.epoch, lower, upper);
                emit ModeApplied(PoolId.unwrap(id), uint8(Mode.NORMAL), lower, upper, d.epoch);
            }
        }
        return (BaseHook.afterSwap.selector, 0);
    }

    function previewPlacement(
        PoolKey calldata key, int24 currTick, int24 homeLower, int24 homeUpper, uint32 sigmaTicks
    ) external view returns (bool useHome, int24 lower, int24 upper) {
        int24 midHome = (homeLower + homeUpper) / 2;
        bool chooseHome = EwmaLib.absDiff(currTick, midHome) <= uint256(cfg.kSigma) * uint256(sigmaTicks);
        if (chooseHome) { return (true, homeLower, homeUpper); }
        int24 s = key.tickSpacing; int24 snapped = currTick - (currTick % s);
        int24 half = int24(int256(uint256(cfg.recenterWidthMult) * uint256(uint24(s))));
        return (false, snapped - half, snapped + half);
    }
}


