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

    address public admin;

    struct Config {
        uint256 thresholdBps;
        uint64 staleAfter;
    }

    Config public config;

    event Signal(bytes32 indexed poolId, uint256 priceE18, uint64 updatedAt);

    uint256 public lastPriceE18;
    bool public hasPrice;

    modifier onlyAdmin() {
        require(msg.sender == admin, "NOT_ADMIN");
        _;
    }

    constructor(bytes32 poolId_, IPriceOracle oracle_, IVault vault_) {
        POOL_ID = poolId_;
        ORACLE = oracle_;
        VAULT = vault_;
        admin = msg.sender;
        config = Config({thresholdBps: 100, staleAfter: 300}); // 1% threshold, 5m staleness
    }

    function setConfig(uint256 thresholdBps, uint64 staleAfter) external onlyAdmin {
        config = Config({thresholdBps: thresholdBps, staleAfter: staleAfter});
    }

    function setAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
    }

    function poke() external {
        (uint256 p, uint64 t) = ORACLE.latestPriceE18(POOL_ID);
        emit Signal(POOL_ID, p, t);
    }

    function check(uint64 epoch) external {
        _check(config.thresholdBps, epoch);
    }

    function check(uint256 thresholdBps, uint64 epoch) external {
        _check(thresholdBps, epoch);
    }

    function _check(uint256 thresholdBps, uint64 epoch) internal {
        (uint256 p, uint64 t) = ORACLE.latestPriceE18(POOL_ID);
        emit Signal(POOL_ID, p, t);

        if (!hasPrice) {
            hasPrice = true;
            lastPriceE18 = p;
            return;
        }

        if (block.timestamp > t && block.timestamp - t > config.staleAfter) {
            return;
        }

        uint256 d = lastPriceE18.bpsDiff(p);
        IVault.Mode m = d >= thresholdBps ? IVault.Mode.WIDENED : IVault.Mode.NORMAL;
        VAULT.applyMode(m, epoch, "");
        lastPriceE18 = p;
    }
}
