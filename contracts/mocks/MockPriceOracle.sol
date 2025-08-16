// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPriceOracle} from "../oracle/IPriceOracle.sol";

contract MockPriceOracle is IPriceOracle {
    mapping(bytes32 => uint256) private _priceE18;
    mapping(bytes32 => uint64)  private _updatedAt;

    event PriceUpdated(bytes32 indexed poolId, uint256 priceE18, uint64 updatedAt);

    function setPrice(bytes32 poolId, uint256 priceE18) external {
        _priceE18[poolId] = priceE18;
        _updatedAt[poolId] = uint64(block.timestamp);
        emit PriceUpdated(poolId, priceE18, _updatedAt[poolId]);
    }

    function latestPriceE18(bytes32 poolId) external view returns (uint256 priceE18, uint64 updatedAt) {
        return (_priceE18[poolId], _updatedAt[poolId]);
    }
}
