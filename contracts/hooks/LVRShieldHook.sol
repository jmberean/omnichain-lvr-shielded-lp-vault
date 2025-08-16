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
        uint256 widenBps;
        uint256 riskOffBps;
        uint64  staleAfter;
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
        ORACLE  = oracle_;
        VAULT   = vault_;
        admin   = msg.sender;
        config  = Config({widenBps: 100, riskOffBps: 500, staleAfter: 300}); // 1% / 5% / 5m
    }

    function setConfig(uint256 widenBps, uint256 riskOffBps, uint64 staleAfter) external onlyAdmin {
        config = Config({widenBps: widenBps, riskOffBps: riskOffBps, staleAfter: staleAfter});
    }

    function setAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
    }

    function poke() external {
        (uint256 p, uint64 t) = ORACLE.latestPriceE18(POOL_ID);
        emit Signal(POOL_ID, p, t);
    }

    // uses stored config
    function check(uint64 epoch) external {
        _check(config.widenBps, config.riskOffBps, epoch);
    }

    // override widen threshold; riskOff from config
    function check(uint256 widenBps, uint64 epoch) external {
        _check(widenBps, config.riskOffBps, epoch);
    }

    function _check(uint256 widenBps, uint256 riskOffBps, uint64 epoch) internal {
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
        IVault.Mode next =
            d >= riskOffBps ? IVault.Mode.RISK_OFF :
            d >= widenBps   ? IVault.Mode.WIDENED  :
                              IVault.Mode.NORMAL;

        IVault.Mode cur = VAULT.currentMode();
        if (next != cur) {
            VAULT.applyMode(next, epoch, "");
        }
        lastPriceE18 = p;
    }
}
