// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

interface ILVRHookReader {
    function cfg() external view returns (uint16 widenBps, uint16 riskOffBps, uint32 minFlipInterval);
    function VAULT() external view returns (address);
}

contract ReadConfig is Script {
    function run() external view {
        address hook = vm.envAddress("HOOK"); // export HOOK=0x...
        (uint16 widen, uint16 risk, uint32 minFlip) = ILVRHookReader(hook).cfg();
        console2.log("Hook:", hook);
        console2.log("Vault:", ILVRHookReader(hook).VAULT());
        console2.log("widenBps:", widen);
        console2.log("riskOffBps:", risk);
        console2.log("minFlipInterval:", minFlip);
    }
}
