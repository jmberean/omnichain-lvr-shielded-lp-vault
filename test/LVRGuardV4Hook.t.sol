// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Vault} from "../contracts/Vault.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {MockPriceOracle} from "../contracts/mocks/MockPriceOracle.sol";
import {LVRGuardV4Hook} from "../contracts/hooks/LVRGuardV4Hook.sol";

contract MockPoolManager is IPoolManager {
    // Implement just enough of the interface to satisfy the compiler and test requirements.
    // Most functions can be empty as they won't be called in this specific test.
    function unlock(bytes calldata) external returns (bytes memory) {}
    function transfer(Currency, address, uint256) external {}
    function mint(address, uint256) external {}
    function burn(address, uint256) external {}
    function settle(Currency) external returns (uint256) {}
    function swap(PoolKey calldata, SwapParams calldata, bytes calldata) external returns (BalanceDelta) {}
    function modifyLiquidity(PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata) external returns (BalanceDelta, BalanceDelta) {}
    function donate(PoolKey calldata, uint128, uint128) external {}
    function take(Currency, address, uint256) external {}
    function initialize(PoolKey calldata, uint160, bytes calldata) external {}
    function getExtsload(bytes32) external view returns (bytes32) {}
    function getPool(PoolId) external view returns (bytes memory) { return ""; }
}

contract LVRGuardV4HookTest is Test {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    Vault vault;
    MockPriceOracle oracle;
    LVRGuardV4Hook hook;
    MockPoolManager mockPoolManager;
    PoolKey poolKey;
    bytes32 poolId;
    IPoolManager.SwapParams swapParams; // Dummy params

    function setUp() public {
        mockPoolManager = new MockPoolManager();
        vault = new Vault(bytes32("POOL"));
        oracle = new MockPriceOracle();
        
        hook = new LVRGuardV4Hook(mockPoolManager, vault, oracle);
        vault.setHook(address(hook));
        
        address token0 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address token1 = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        Currency currency0 = CurrencyLibrary.wrap(token0);
        Currency currency1 = CurrencyLibrary.wrap(token1);
        poolKey = PoolKey(currency0, currency1, 3000, 60, address(hook));
        poolId = poolKey.toId();
        
        swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: 0
        });
    }
    
    // A public wrapper to test the internal _afterSwap function
    function afterSwap(PoolKey calldata key, IPoolManager.SwapParams calldata params, BalanceDelta delta, bytes calldata data) public {
        hook.afterSwap(msg.sender, key, params, delta, data);
    }
    
    function testPermissions() public {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.afterSwap);
        assertFalse(permissions.beforeSwap);
    }

    function testStateChangeToWidened() public {
        oracle.setPrice(poolId, 1000e18);

        // Simulate first swap to set initial price
        vm.prank(address(mockPoolManager));
        afterSwap(poolKey, swapParams, BalanceDelta.zero(), "");
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.NORMAL));

        // Price moves by 1.1% (110 bps), which is > 100 bps threshold
        oracle.setPrice(poolId, 1011e18);

        vm.expectEmit(true, true, true, true);
        emit IVault.ModeApplied(poolId, uint8(IVault.Mode.WIDENED), block.timestamp, "Volatility trigger");

        // Simulate second swap
        vm.prank(address(mockPoolManager));
        afterSwap(poolKey, swapParams, BalanceDelta.zero(), "");
        
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.WIDENED));
    }

    function testStateChangeToRiskOff() public {
        oracle.setPrice(poolId, 1000e18);

        // Simulate first swap
        vm.prank(address(mockPoolManager));
        afterSwap(poolKey, swapParams, BalanceDelta.zero(), "");
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.NORMAL));

        // Price moves by 5.5% (550 bps), which is > 500 bps threshold
        oracle.setPrice(poolId, 1055e18);

        vm.expectEmit(true, true, true, true);
        emit IVault.ModeApplied(poolId, uint8(IVault.Mode.RISK_OFF), block.timestamp, "Volatility trigger");
        
        // Simulate second swap
        vm.prank(address(mockPoolManager));
        afterSwap(poolKey, swapParams, BalanceDelta.zero(), "");
        
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.RISK_OFF));
    }

    function testNoStateChangeWhenBelowThreshold() public {
        oracle.setPrice(poolId, 1000e18);

        // Simulate first swap
        vm.prank(address(mockPoolManager));
        afterSwap(poolKey, swapParams, BalanceDelta.zero(), "");
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.NORMAL));
        
        // Price moves by 0.5% (50 bps), which is below all thresholds
        oracle.setPrice(poolId, 1005e18);

        // Simulate second swap
        vm.prank(address(mockPoolManager));
        afterSwap(poolKey, swapParams, BalanceDelta.zero(), "");

        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.NORMAL));
    }
}