// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

interface ILVRHookAdmin {
    function setLVRConfig(uint16 widenBps, uint16 riskOffBps, uint32 minFlipInterval) external;
    function VAULT() external view returns (address);
}

contract SetConfig is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address hook = vm.envAddress("HOOK"); // export HOOK=0x...

        uint16 widen = uint16(vm.envUint("WIDEN_BPS"));        // e.g. 100 = 1%
        uint16 risk  = uint16(vm.envUint("RISK_OFF_BPS"));     // e.g. 1000 = 10%
        uint32 flip  = uint32(vm.envUint("MIN_FLIP_INTERVAL")); // seconds, e.g. 300

        vm.startBroadcast(pk);
        ILVRHookAdmin(hook).setLVRConfig(widen, risk, flip);
        vm.stopBroadcast();

        console2.log("Hook       :", hook);
        console2.log("VAULT      :", ILVRHookAdmin(hook).VAULT());
        console2.log("widenBps   :", widen);
        console2.log("riskOffBps :", risk);
        console2.log("minFlipInt :", flip);
    }
}
