// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {Vault} from "../contracts/Vault.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";
import {MockPriceOracle} from "../contracts/oracle/MockPriceOracle.sol";

contract VaultIntegrationTest is Test {
    Vault internal vault;
    LVRShieldHook internal hook;
    MockPriceOracle internal oracle;

    bytes32 constant TEST_POOL = bytes32(uint256(0x1234));
    
    event ModeApplied(
        bytes32 indexed poolId,
        uint8 mode,
        uint64 epoch,
        string reason,
        int24 centerTick,
        int24 halfWidthTicks
    );

    function setUp() public {
        vault = new Vault(address(this));
        oracle = new MockPriceOracle(address(this));
        
        // Mine correct address for hook
        IPoolManager manager = IPoolManager(address(0xdead));
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.AFTER_ADD_LIQUIDITY_FLAG
        );
        
        bytes memory ctorArgs = abi.encode(manager, IVault(address(vault)), oracle, address(this));
        
        (address predicted, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(LVRShieldHook).creationCode,
            ctorArgs
        );
        
        hook = new LVRShieldHook{salt: salt}(
            manager,
            IVault(address(vault)),
            oracle,
            address(this)
        );
        
        require(address(hook) == predicted, "hook address mismatch");
        
        vault.setHook(address(hook));
        vault.setKeeper(address(this));
    }

    function testHookCanApplyMode() public {
        vm.expectEmit(true, false, false, true, address(vault));
        emit ModeApplied(TEST_POOL, 1, 10, "volatility", 100, 50);
        
        vm.prank(address(hook));
        vault.applyMode(
            TEST_POOL,
            IVault.Mode.WIDENED,
            10,
            "volatility",
            100,
            50
        );
        
        (int24 center, int24 width) = vault.getHome(TEST_POOL);
        assertEq(center, 100);
        assertEq(width, 50);
    }

    function testOnlyHookCanApplyMode() public {
        vm.prank(address(0xbeef));
        vm.expectRevert("VAULT:NOT_HOOK");
        vault.applyMode(TEST_POOL, IVault.Mode.NORMAL, 1, "test", 0, 0);
    }

    function testKeeperCanRebalance() public {
        vault.keeperRebalance(
            TEST_POOL,
            200,
            75,
            "rebalance",
            uint8(IVault.Mode.NORMAL),
            5
        );
        
        (int24 center, int24 width) = vault.getHome(TEST_POOL);
        assertEq(center, 200);
        assertEq(width, 75);
    }
}
