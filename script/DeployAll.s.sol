pragma solidity ^0.8.26;
import "forge-std/Script.sol";
import {Vault} from "../contracts/Vault.sol";
import {MockPriceOracle} from "../contracts/oracle/MockPriceOracle.sol";
import {HookCreate2Factory} from "../contracts/utils/HookCreate2Factory.sol";

contract DeployAll is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        Vault vault = new Vault(deployer);
        MockPriceOracle oracle = new MockPriceOracle(deployer);
        HookCreate2Factory factory = new HookCreate2Factory();
        vault.setKeeper(deployer);
        
        vm.stopBroadcast();
        
        console2.log("VAULT:", address(vault));
        console2.log("ORACLE:", address(oracle));
        console2.log("FACTORY:", address(factory));
    }
}
