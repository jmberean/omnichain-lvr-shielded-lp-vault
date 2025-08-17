// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Small helper for bps math with overflow checks.
library PriceMath {
    /// @dev Applies +/- basis points to a value (e.g., dynamic fee computation).
    ///      bps is signed: +100 = +1%, -50 = -0.5%.
    function applyBps(uint256 value, int256 bps) internal pure returns (uint256) {
        if (bps == 0) return value;
        if (bps > 0) {
            uint256 num = value * (uint256(10_000) + uint256(bps));
            return num / 10_000;
        } else {
            uint256 abs = uint256(-bps);
            require(abs <= 10_000, "BPS:UNDERFLOW");
            uint256 num2 = value * (10_000 - abs);
            return num2 / 10_000;
        }
    }
}
