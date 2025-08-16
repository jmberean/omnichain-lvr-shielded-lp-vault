// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../contracts/Vault.sol";
import {IVault} from "../contracts/interfaces/IVault.sol";

contract VaultKeeperTest is Test {
    Vault vault;
    bytes32 constant POOL_ID = bytes32("POOL");

    event LiquidityAction(bytes32 indexed poolId, uint8 mode, uint64 epoch, int256 baseDelta, int256 quoteDelta, string reason);

    function setUp() public {
        vault = new Vault(POOL_ID);
        vault.setHook(address(this));
        vault.setKeeper(address(this));
        vault.applyMode(IVault.Mode.WIDENED, 3, "");
    }

    function testKeeperRebalanceEmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(vault));
        emit LiquidityAction(POOL_ID, uint8(IVault.Mode.WIDENED), 3, int256(1e18), int256(-5e18), "rebalance");
        vault.keeperRebalance(int256(1e18), int256(-5e18), "rebalance");
    }
}
