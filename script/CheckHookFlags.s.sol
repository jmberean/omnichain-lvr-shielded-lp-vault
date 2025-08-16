// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Script.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
contract CheckHookFlags is Script {
    function run() external view {
        address hook = vm.envAddress("HOOK_ADDR");
        uint160 a = uint160(hook);
        console2.log("Hook @", hook);
        console2.log("afterSwap:", (a & uint160(Hooks.AFTER_SWAP_FLAG)) != 0);
        console2.log("beforeSwap:", (a & uint160(Hooks.BEFORE_SWAP_FLAG)) != 0);
        console2.log("beforeInitialize:", (a & uint160(Hooks.BEFORE_INITIALIZE_FLAG)) != 0);
        console2.log("afterInitialize :", (a & uint160(Hooks.AFTER_INITIALIZE_FLAG)) != 0);
        console2.log("afterAddLiquidity:", (a & uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG)) != 0);
        console2.log("afterRemoveLiquidity:", (a & uint160(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG)) != 0);
        console2.log("beforeDonate:", (a & uint160(Hooks.BEFORE_DONATE_FLAG)) != 0);
        console2.log("afterDonate:", (a & uint160(Hooks.AFTER_DONATE_FLAG)) != 0);
    }
}


