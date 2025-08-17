// script/QuickDeploy.s.sol
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {Vault} from "../contracts/Vault.sol";
import {MockPriceOracle} from "../contracts/oracle/MockPriceOracle.sol";
import {HookCreate2Factory} from "../contracts/utils/HookCreate2Factory.sol";

contract QuickDeploy is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        
        address deployer = msg.sender;
        
        Vault vault = new Vault(deployer);
        MockPriceOracle oracle = new MockPriceOracle(deployer);
        HookCreate2Factory factory = new HookCreate2Factory();
        
        console2.log("Vault:", address(vault));
        console2.log("Oracle:", address(oracle));
        console2.log("Factory:", address(factory));
        
        vm.stopBroadcast();
    }
}