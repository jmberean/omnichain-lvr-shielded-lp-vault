// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library HookFlags {
  uint160 constant BEFORE_SWAP_FLAG          = 1 << 7;   // 0x0080
  uint160 constant AFTER_SWAP_FLAG           = 1 << 6;   // 0x0040
  uint160 constant BEFORE_ADD_LIQUIDITY_FLAG = 1 << 11;  // 0x0800
  uint160 constant AFTER_ADD_LIQUIDITY_FLAG  = 1 << 10;  // 0x0400

  // For LVR-Shield
  uint160 constant FLAGS = BEFORE_SWAP_FLAG | AFTER_SWAP_FLAG | AFTER_ADD_LIQUIDITY_FLAG; // 0x04C0
}
