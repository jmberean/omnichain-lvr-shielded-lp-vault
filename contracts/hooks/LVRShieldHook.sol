// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPriceOracle} from "../oracle/IPriceOracle.sol";
import {IVault} from "../interfaces/IVault.sol";
import {PriceMath} from "../libraries/PriceMath.sol";

contract LVRShieldHook {
    using PriceMath for uint256;

    bytes32 public immutable POOL_ID;
    IPriceOracle public immutable ORACLE;
    IVault public immutable VAULT;

    event Signal(bytes32 indexed poolId, uint256 priceE18, uint64 updatedAt);

    uint256 public lastPriceE18;
    bool public hasPrice;

    constructor(bytes32 poolId_, IPriceOracle oracle_, IVault vault_) {
        POOL_ID = poolId_;
        ORACLE = oracle_;
        VAULT = vault_;
    }

    function poke() external {
        (uint256 p, uint64 t) = ORACLE.latestPriceE18(POOL_ID);
        emit Signal(POOL_ID, p, t);
    }

    function check(uint256 thresholdBps, uint64 epoch) external {
        (uint256 p, uint64 t) = ORACLE.latestPriceE18(POOL_ID);
        emit Signal(POOL_ID, p, t);

        if (!hasPrice) {
            hasPrice = true;
            lastPriceE18 = p;
            return;
        }

        uint256 d = lastPriceE18.bpsDiff(p);
        IVault.Mode m = d >= thresholdBps ? IVault.Mode.WIDENED : IVault.Mode.NORMAL;
        VAULT.applyMode(m, epoch, "");
        lastPriceE18 = p;
    }
}
