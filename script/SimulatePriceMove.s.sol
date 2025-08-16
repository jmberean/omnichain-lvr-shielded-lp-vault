// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";
import {MockPriceOracle} from "../contracts/mocks/MockPriceOracle.sol";
import {LVRShieldHook} from "../contracts/hooks/v4/LVRShieldHook.sol";

contract SimulatePriceMove is Script {
    // usage:
    // forge script script/SimulatePriceMove.s.sol:SimulatePriceMove \
    //   --sig "run(address,address,uint256,uint64,uint256)" <HOOK> <ORACLE> <PRICE_E18> <EPOCH> <THRESH_BPS> ...
    function run(
        address hookAddr,
        address oracleAddr,
        uint256 priceE18,
        uint64 epoch,
        uint256 thresholdBps
    ) external {
        vm.startBroadcast();

        LVRShieldHook hook = LVRShieldHook(hookAddr);
        MockPriceOracle oracle = MockPriceOracle(oracleAddr);

        bytes32 pid = hook.POOL_ID();
        oracle.setPrice(pid, priceE18);
        hook.check(thresholdBps, epoch);

        IVault.Mode m = IVault(address(hook.VAULT())).currentMode();
        console.log("mode:", uint8(m));

        vm.stopBroadcast();
    }
}
