// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Compatibility shim for legacy imports in scripts/tests.
// It simply imports the real oracle from the new location.
import "../oracle/MockPriceOracle.sol";
