// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library EwmaLib {
    /// @notice EWMA with alpha in ppm (0..1e6). Floor division.
    function step(uint256 prev, uint256 sample, uint32 alphaPpm) internal pure returns (uint256) {
        unchecked { return (prev * (1_000_000 - alphaPpm) + sample * alphaPpm) / 1_000_000; }
    }
}
