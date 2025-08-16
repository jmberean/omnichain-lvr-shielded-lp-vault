// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library PriceMath {
    function bpsDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == b) return 0;
        uint256 max = a > b ? a : b;
        uint256 min = a > b ? b : a;
        unchecked {
            uint256 diff = max - min;
            return (diff * 10_000) / max;
        }
    }

    function applyBps(uint256 value, int256 bps) internal pure returns (uint256) {
        if (bps == 0) return value;
        if (bps > 0) {
            return value + (value * uint256(bps) / 10_000);
        } else {
            return value - (value * uint256(-bps) / 10_000);
        }
    }
}
