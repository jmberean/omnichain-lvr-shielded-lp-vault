// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceOracle} from "./IPriceOracle.sol";

/// @notice Simple mock: set and read price by id (1e18 scale).
contract MockPriceOracle is IPriceOracle {
    address public immutable admin;
    mapping(bytes32 => uint256) private _price;
    mapping(bytes32 => uint64) private _time;

    modifier onlyAdmin() {
        require(msg.sender == admin, "ORACLE:NOT_ADMIN");
        _;
    }

    constructor(address admin_) {
        require(admin_ != address(0), "ORACLE:BAD_ADMIN");
        admin = admin_;
    }

    function set(bytes32 id, uint256 priceE18, uint64 publishTime) external onlyAdmin {
        _price[id] = priceE18;
        _time[id] = publishTime;
    }

    function getPriceE18(bytes32 id) external view returns (uint256 priceE18, uint64 publishTime) {
        return (_price[id], _time[id]);
    }
}
