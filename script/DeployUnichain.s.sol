// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {HookMiner} from "v4-periphery/utils/HookMiner.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Vault} from "../contracts/Vault.sol";
import {LVRGuardV4Hook} from "../contracts/hooks/LVRGuardV4Hook.sol";
import {IPriceOracle} from "../contracts/oracle/IPriceOracle.sol";

/**
 * @title DeployUnichain
 * @notice Deployment script for Unichain (Sepolia testnet)
 * @dev Deploys Vault, Oracle, and mined Hook address
 */
contract DeployUnichain is Script {
    using PoolIdLibrary for PoolKey;
    
    // Unichain Sepolia addresses
    address constant UNICHAIN_POOL_MANAGER = 0x2B56AeC709c446D21c5DA653eD2db951d6A33cC5; // Example address
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920ca78fbf26c0b4956c;
    
    // Token addresses on Unichain Sepolia (example addresses)
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    
    // Configuration
    uint24 constant POOL_FEE = 3000; // 0.3%
    int24 constant TICK_SPACING = 60;
    uint160 constant SQRT_PRICE_X96 = 79228162514264337593543950336; // 1:1 price
    
    function run() external {
        // Load deployment private key
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Unichain Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Pool Manager:", UNICHAIN_POOL_MANAGER);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy Oracle (use mock for testnet, replace with Pyth/Chainlink for mainnet)
        IPriceOracle oracle = _deployOracle();
        
        // 2. Create pool key
        PoolKey memory poolKey = _createPoolKey();
        bytes32 poolId = poolKey.toId();
        
        console.log("Pool ID:", vm.toString(poolId));
        
        // 3. Deploy Vault
        Vault vault = new Vault{salt: keccak256("LVR_VAULT_V1")}(poolId);
        console.log("Vault deployed:", address(vault));
        
        // 4. Mine and deploy Hook
        LVRGuardV4Hook hook = _deployHook(vault, oracle);
        console.log("Hook deployed:", address(hook));
        
        // 5. Configure Vault
        vault.setHook(address(hook));
        vault.setKeeper(deployer); // Set deployer as initial keeper
        
        // 6. Configure re-entry parameters
        vault.setReentryConfig(
            300,    // 5 minute cooldown
            1e18,   // Minimum liquidity threshold
            8000,   // 80% max exposure
            false   // Auto re-entry disabled initially
        );
        
        // 7. Initialize pool if needed
        _initializePool(poolKey);
        
        // 8. Log deployment summary
        _logDeploymentSummary(vault, hook, oracle, poolId);
        
        // 9. Write deployment artifacts
        _writeDeploymentArtifacts(vault, hook, oracle, poolId);
        
        vm.stopBroadcast();
    }
    
    function _deployOracle() private returns (IPriceOracle) {
        // For mainnet, integrate with Pyth or Chainlink
        // For testnet, deploy mock oracle
        console.log("Deploying price oracle...");
        
        // Example: Deploy mock oracle for testing
        // In production, use:
        // return IPriceOracle(0x...); // Pyth/Chainlink address
        
        // Mock oracle deployment (replace with real oracle integration)
        bytes memory bytecode = abi.encodePacked(
            vm.getCode("MockPriceOracle.sol:MockPriceOracle")
        );
        address oracle;
        assembly {
            oracle := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        
        console.log("Oracle deployed:", oracle);
        return IPriceOracle(oracle);
    }
    
    function _createPoolKey() private pure returns (PoolKey memory) {
        Currency currency0 = Currency.wrap(WETH);
        Currency currency1 = Currency.wrap(USDC);
        
        // Ensure correct token ordering
        if (uint160(WETH) > uint160(USDC)) {
            (currency0, currency1) = (currency1, currency0);
        }
        
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: address(0) // Will be updated after hook deployment
        });
    }
    
    function _deployHook(
        Vault vault,
        IPriceOracle oracle
    ) private returns (LVRGuardV4Hook) {
        console.log("Mining hook address...");
        
        // Define hook permissions (only afterSwap)
        uint160 flags = Hooks.AFTER_SWAP_FLAG;
        
        // Prepare constructor arguments
        bytes memory constructorArgs = abi.encode(
            IPoolManager(UNICHAIN_POOL_MANAGER),
            vault,
            oracle
        );
        
        // Mine the correct address
        (address expectedHookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(LVRGuardV4Hook).creationCode,
            constructorArgs
        );
        
        console.log("Expected hook address:", expectedHookAddress);
        console.log("Salt:", vm.toString(salt));
        
        // Deploy hook at mined address
        LVRGuardV4Hook hook = new LVRGuardV4Hook{salt: salt}(
            IPoolManager(UNICHAIN_POOL_MANAGER),
            vault,
            oracle
        );
        
        require(
            address(hook) == expectedHookAddress,
            "Hook address mismatch - mining failed"
        );
        
        // Configure hook parameters
        hook.setConfig(
            100,  // 1% widen threshold
            500,  // 5% risk-off threshold
            300   // 5 minute staleness
        );
        
        return hook;
    }
    
    function _initializePool(PoolKey memory poolKey) private {
        console.log("Initializing pool...");
        
        IPoolManager poolManager = IPoolManager(UNICHAIN_POOL_MANAGER);
        
        // Check if pool already exists
        try poolManager.getPool(poolKey.toId()) returns (bytes memory poolData) {
            if (poolData.length > 0) {
                console.log("Pool already initialized");
                return;
            }
        } catch {
            // Pool doesn't exist, continue with initialization
        }
        
        // Initialize the pool
        poolManager.initialize(poolKey, SQRT_PRICE_X96, "");
        console.log("Pool initialized with price 1:1");
    }
    
    function _logDeploymentSummary(
        Vault vault,
        LVRGuardV4Hook hook,
        IPriceOracle oracle,
        bytes32 poolId
    ) private view {
        console.log("\n=== Deployment Summary ===");
        console.log("Network: Unichain Sepolia");
        console.log("Vault:", address(vault));
        console.log("Hook:", address(hook));
        console.log("Oracle:", address(oracle));
        console.log("Pool ID:", vm.toString(poolId));
        console.log("Admin:", vault.admin());
        console.log("Keeper:", vault.keeper());
        console.log("\n=== Configuration ===");
        console.log("Widen Threshold: 1%");
        console.log("Risk-off Threshold: 5%");
        console.log("Staleness: 5 minutes");
        console.log("Cooldown: 5 minutes");
        console.log("Max Exposure: 80%");
    }
    
    function _writeDeploymentArtifacts(
        Vault vault,
        LVRGuardV4Hook hook,
        IPriceOracle oracle,
        bytes32 poolId
    ) private {
        string memory json = "deploymentArtifact";
        
        vm.serializeAddress(json, "vault", address(vault));
        vm.serializeAddress(json, "hook", address(hook));
        vm.serializeAddress(json, "oracle", address(oracle));
        vm.serializeBytes32(json, "poolId", poolId);
        vm.serializeUint(json, "timestamp", block.timestamp);
        vm.serializeUint(json, "chainId", block.chainid);
        
        string memory finalJson = vm.serializeString(
            json,
            "network",
            "unichain-sepolia"
        );
        
        vm.writeJson(
            finalJson,
            string.concat("./deployments/unichain-", vm.toString(block.timestamp), ".json")
        );
        
        console.log("Deployment artifacts written to ./deployments/");
    }
}