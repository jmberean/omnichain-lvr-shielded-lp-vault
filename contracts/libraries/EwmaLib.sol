// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
library EwmaLib {
    function update(uint256 prev, uint256 sampleAbs, uint32 alphaPPM) internal pure returns (uint256) {
        unchecked {
            uint256 ONE = 1_000_000;
            uint256 a = alphaPPM;
            uint256 inv = ONE - a;
            return (prev * inv + sampleAbs * a) / ONE;
        }
    }
    function absDiff(int24 a, int24 b) internal pure returns (uint256) {
        return a >= b ? uint256(int256(a - b)) : uint256(int256(b - a));
    }
}

