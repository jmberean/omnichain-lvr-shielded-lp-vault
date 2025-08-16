// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IPriceOracle {
    function latestPriceE18(bytes32 poolId) external view returns (uint256 priceE18, uint64 updatedAt);
}
