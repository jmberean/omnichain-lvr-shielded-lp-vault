pragma solidity ^0.8.26;
import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {IPriceOracle} from "../contracts/oracle/IPriceOracle.sol";
import {HookCreate2Factory} from "../contracts/utils/HookCreate2Factory.sol";
import {Vault} from "../contracts/Vault.sol";

contract DeployHookAuto is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address vault = vm.envAddress("VAULT");
        address oracle = vm.envAddress("ORACLE");
        address factory = vm.envAddress("FACTORY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        IPoolManager manager = IPoolManager(address(0xFEE1));
        bytes memory ctorArgs = abi.encode(manager, IVault(vault), IPriceOracle(oracle), deployer);
        
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.AFTER_ADD_LIQUIDITY_FLAG
        );
        
        (address predicted, bytes32 salt) = HookMiner.find(
            factory, flags, type(LVRShieldHook).creationCode, ctorArgs
        );
        
        bytes memory initcode = abi.encodePacked(type(LVRShieldHook).creationCode, ctorArgs);
        address hook = HookCreate2Factory(factory).deploy(salt, initcode);
        
        Vault(vault).setHook(hook);
        LVRShieldHook(payable(hook)).setLVRConfig(100, 500, 300);
        
        vm.stopBroadcast();
        
        console2.log("HOOK:", hook);
        console2.log("SALT:", uint256(salt));
    }
}
