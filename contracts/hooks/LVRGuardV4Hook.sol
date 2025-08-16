// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/hooks/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IPriceOracle} from "../oracle/IPriceOracle.sol";
import {PriceMath} from "../libraries/PriceMath.sol";

contract LVRGuardV4Hook is BaseHook {
    using PriceMath for uint256;

    IVault public immutable VAULT;
    IPriceOracle public immutable ORACLE;

    uint256 public lastPriceE18;
    bool public hasPrice;

    struct Config {
        uint256 widenBps;
        uint256 riskOffBps;
        uint64 staleAfter;
    }

    Config public config;

    event Signal(bytes32 indexed poolId, uint256 priceE18, uint64 updatedAt);

    constructor(IPoolManager _poolManager, IVault _vault, IPriceOracle _oracle) BaseHook(_poolManager) {
        VAULT = _vault;
        ORACLE = _oracle;
        config = Config({widenBps: 100, riskOffBps: 500, staleAfter: 300}); // 1% / 5% / 5m
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            noOpDelta: false,
            mustSwapInexact: false,
            mustSwapExact: false
        });
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        bytes32 poolId = key.toId();
        (uint256 p, uint64 t) = ORACLE.latestPriceE18(poolId);
        emit Signal(poolId, p, t);

        if (!hasPrice) {
            hasPrice = true;
            lastPriceE18 = p;
            return (BaseHook.afterSwap.selector, 0);
        }

        if (block.timestamp > t && block.timestamp - t > config.staleAfter) {
            return (BaseHook.afterSwap.selector, 0);
        }

        uint256 d = lastPriceE18.bpsDiff(p);
        IVault.Mode next = d >= config.riskOffBps
            ? IVault.Mode.RISK_OFF
            : d >= config.widenBps
            ? IVault.Mode.WIDENED
            : IVault.Mode.NORMAL;

        IVault.Mode cur = VAULT.currentMode();
        if (next != cur) {
            VAULT.applyMode(next, uint64(block.timestamp), "");
        }
        lastPriceE18 = p;

        return (BaseHook.afterSwap.selector, 0);
    }

    function setConfig(uint256 widenBps, uint256 riskOffBps, uint64 staleAfter) external {
        config = Config({widenBps: widenBps, riskOffBps: riskOffBps, staleAfter: staleAfter});
    }
}