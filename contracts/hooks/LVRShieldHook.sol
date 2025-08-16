// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPriceOracle} from "../oracle/IPriceOracle.sol";

contract LVRShieldHook {
    bytes32 public immutable POOL_ID;
    IPriceOracle public immutable ORACLE;

    event Signal(bytes32 indexed poolId, uint256 priceE18, uint64 updatedAt);

    constructor(bytes32 poolId_, IPriceOracle oracle_) {
        POOL_ID = poolId_;
        ORACLE = oracle_;
    }

    function poke() external {
        (uint256 p, uint64 t) = ORACLE.latestPriceE18(POOL_ID);
        emit Signal(POOL_ID, p, t);
    }
}
