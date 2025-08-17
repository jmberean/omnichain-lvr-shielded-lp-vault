// script/DirectDeploy.s.sol
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {Vault} from "../contracts/Vault.sol";
import {MockPriceOracle} from "../contracts/oracle/MockPriceOracle.sol";
import {HookCreate2Factory} from "../contracts/utils/HookCreate2Factory.sol";

contract DirectDeploy is Script {
    function run() external {
        // Hardcode the private key to avoid Git Bash issues
        uint256 pk = 0x9a12079cebb28de053f07d1e38687c278af265c4ab378de24cd2ef4119c69c51;
        address deployer = vm.addr(pk);
        
        console2.log("Deployer:", deployer);
        
        vm.startBroadcast(pk);
        
        // Deploy all contracts
        Vault vault = new Vault(deployer);
        console2.log("Vault:", address(vault));
        
        MockPriceOracle oracle = new MockPriceOracle(deployer);
        console2.log("Oracle:", address(oracle));
        
        HookCreate2Factory factory = new HookCreate2Factory();
        console2.log("Factory:", address(factory));
        
        // Wire vault
        vault.setKeeper(deployer);
        
        vm.stopBroadcast();
        
        // Output for copy-paste
        console2.log("\nExport these:");
        console2.log(string.concat("export VAULT=", vm.toString(address(vault))));
        console2.log(string.concat("export ORACLE=", vm.toString(address(oracle))));
        console2.log(string.concat("export FACTORY=", vm.toString(address(factory))));
    }
}