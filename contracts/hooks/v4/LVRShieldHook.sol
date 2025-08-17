// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Uniswap v4 core
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

// v4-periphery BaseHook (utils path)
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

// Local
import {IVault} from "../../interfaces/IVault.sol";

contract LVRShieldHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    IVault public immutable VAULT;
    address public immutable ADMIN;

    struct LvrConfig {
        uint16 widenBps;
        uint16 riskOffBps;
        uint32 minFlipInterval;
    }
    LvrConfig public cfg;

    event Signal(PoolId indexed poolId, uint8 code, string tag);
    event ConfigUpdated(uint16 widenBps, uint16 riskOffBps, uint32 minFlipInterval);

    constructor(IPoolManager manager, IVault vault, address admin) BaseHook(manager) {
        require(address(vault) != address(0), "vault=0");
        require(admin != address(0), "admin=0");
        VAULT = vault;
        ADMIN = admin;

        // Enforce permissions-encoded address
        Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory p) {
        p.beforeSwap = true;
        p.afterSwap = true;
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        emit Signal(key.toId(), 1, "beforeSwap");
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address,
        PoolKey calldata /* key */,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal pure override returns (bytes4, int128) {
        return (BaseHook.afterSwap.selector, int128(0));
    }

    // -------- Demo passthrough (to satisfy Vault.onlyHook) --------
    function adminApplyModeForDemo(
        PoolId poolId,
        IVault.Mode mode,
        uint64 epoch,
        string calldata reason,
        int24 centerTick,
        int24 halfWidthTicks
    ) external {
        require(msg.sender == ADMIN, "not admin");
        bytes32 pid = PoolId.unwrap(poolId);
        VAULT.applyMode(pid, mode, epoch, reason, centerTick, halfWidthTicks);
        emit Signal(poolId, 3, "adminApplyModeForDemo");
    }

    function setLvrConfig(uint16 widenBps, uint16 riskOffBps, uint32 minFlipInterval) external {
        require(msg.sender == ADMIN, "not admin");
        cfg = LvrConfig(widenBps, riskOffBps, minFlipInterval);
        emit ConfigUpdated(widenBps, riskOffBps, minFlipInterval);
    }
}
