// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// BaseHook from periphery
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

// Core libs & types
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

// Local
import {IVault} from "../../interfaces/IVault.sol";

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

    constructor(IPoolManager _manager, IVault _vault, address _admin)
        BaseHook(_manager)
    {
        require(address(_vault) != address(0), "HOOK:BAD_VAULT");
        require(_admin != address(0), "HOOK:BAD_ADMIN");
        vault = _vault;
        admin = _admin;

        Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory p)
    {
        p.beforeSwap = true;
        p.afterSwap = true;
        p.beforeSwapReturnDelta = false;
        p.afterSwapReturnDelta = false;
    }

    function _beforeSwap(
        address,              // sender
        PoolKey calldata key, // pool key
        SwapParams calldata,  // params
        bytes calldata        // hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        emit Signal(PoolId.unwrap(key.toId()), 0, "noop");
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address,             // sender
        PoolKey calldata,    // key
        SwapParams calldata, // params
        BalanceDelta,        // delta
        bytes calldata       // hookData
    ) internal override returns (bytes4, int128) {
        return (BaseHook.afterSwap.selector, int128(0));
    }

    // --- Admin demo helper (until full PM wiring is live) ---
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
        cfg[poolId] = LVRConfig(widenBps, riskOffBps, minFlipIntervalSec);
    }
}
