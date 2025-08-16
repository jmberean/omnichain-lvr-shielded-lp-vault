// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../contracts/Vault.sol";
import {LVRGuardV4Hook} from "../contracts/hooks/LVRGuardV4Hook.sol";

contract CompileTest is Test {
    function testCompiles() public pure {
        // Just test that everything compiles
        assertTrue(true);
    }
}