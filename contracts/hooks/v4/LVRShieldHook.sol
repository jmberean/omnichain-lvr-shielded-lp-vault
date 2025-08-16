// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// === Uniswap v4 ===
// BaseHook is in v4-periphery; Hooks & types are in v4-core.
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

// === Local ===
import {IVault} from "../../interfaces/IVault.sol";

/// @title LVRShieldHook (minimal, compile-safe scaffold)
contract LVRShieldHook is BaseHook {
    IVault public immutable vault;
    address public immutable admin;

    struct LVRConfig {
        uint24 widenBps;
        uint24 riskOffBps;
        uint32 minFlipIntervalSec;
    }
    mapping(bytes32 => LVRConfig) public cfg;

    event Signal(bytes32 indexed poolId, uint64 epoch, string reason);

    modifier onlyAdmin() {
        require(msg.sender == admin, "HOOK:NOT_ADMIN");
        _;
    }

    constructor(IPoolManager _poolManager, IVault _vault, address _admin)
        BaseHook(_poolManager)
    {
        require(address(_vault) != address(0), "HOOK:BAD_VAULT");
        require(_admin != address(0), "HOOK:BAD_ADMIN");
        vault = _vault;
        admin = _admin;

        Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
    }

    function getHookPermissions() public pure override returns (HookPermissions memory p) {
        p.beforeSwap = true; // minimal safe set
    }

    function _beforeSwap(
        address, /* sender */
        PoolKey calldata key,
        IPoolManager.SwapParams calldata, /* params */
        bytes calldata /* hookData */
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        emit Signal(key.toId(), 0, "noop");
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    // Admin convenience for demo
    function adminApplyModeForDemo(
        bytes32 poolId,
        IVault.Mode mode_,
        uint64 epoch,
        string calldata reason,
        int24 centerTick,
        int24 halfWidthTicks
    ) external onlyAdmin {
        vault.applyMode(poolId, mode_, epoch, reason, centerTick, halfWidthTicks);
        emit Signal(poolId, epoch, reason);
    }

    function setLVRConfig(
        bytes32 poolId,
        uint24 widenBps,
        uint24 riskOffBps,
        uint32 minFlipIntervalSec
    ) external onlyAdmin {
        cfg[poolId] = LVRConfig({
            widenBps: widenBps,
            riskOffBps: riskOffBps,
            minFlipIntervalSec: minFlipIntervalSec
        });
    }
}
