// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../contracts/Vault.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";

contract BuildTest is Test {
    Vault vault;
    
    function setUp() public {
        bytes32 poolId = keccak256("TEST_POOL");
        vault = new Vault(poolId);
    }
    
    function testVaultBasics() public view {
        assertEq(vault.poolId(), keccak256("TEST_POOL"));
        assertEq(uint8(vault.currentMode()), uint8(IVault.Mode.NORMAL));
        assertEq(vault.modeEpoch(), 0);
        assertEq(vault.admin(), address(this));
    }
    
    function testVaultSetters() public {
        address newKeeper = address(0x123);
        vault.setKeeper(newKeeper);
        assertEq(vault.keeper(), newKeeper);
        
        address newHook = address(0x456);
        vault.setHook(newHook);
        assertEq(vault.hook(), newHook);
    }
}