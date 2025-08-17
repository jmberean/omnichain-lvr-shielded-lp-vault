// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal interface for a price oracle returning 1e18 fixed-point prices.
interface IPriceOracle {
    /// @return priceE18 price scaled by 1e18
    /// @return publishTime Unix timestamp of the price
    function getPriceE18(bytes32 priceId) external view returns (uint256 priceE18, uint64 publishTime);
}
