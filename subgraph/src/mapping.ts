import {
  ModeApplied as ModeAppliedEvent,
  LiquidityAction as LiquidityActionEvent,
} from "../generated/Vault/Vault";
import { Signal as SignalEvent } from "../generated/LVRShieldHook/LVRShieldHook";

import { ModeApplied, LiquidityAction, Signal } from "../generated/schema";

export function handleModeApplied(event: ModeAppliedEvent): void {
  const id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  const e = new ModeApplied(id);
  e.poolId = event.params.poolId;
  e.mode = event.params.mode;              // uint8 -> i32 in AS, schema uses Int
  e.epoch = event.params.epoch;            // already BigInt
  e.reason = event.params.reason;
  e.txHash = event.transaction.hash;
  e.blockNumber = event.block.number;
  e.save();
}

export function handleLiquidityAction(event: LiquidityActionEvent): void {
  const id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  const e = new LiquidityAction(id);
  e.poolId = event.params.poolId;
  e.mode = event.params.mode;
  e.epoch = event.params.epoch;            // already BigInt
  e.baseDelta = event.params.baseDelta;    // int256 -> BigInt
  e.quoteDelta = event.params.quoteDelta;  // int256 -> BigInt
  e.reason = event.params.reason;
  e.txHash = event.transaction.hash;
  e.blockNumber = event.block.number;
  e.save();
}

export function handleSignal(event: SignalEvent): void {
  const id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  const s = new Signal(id);
  s.poolId = event.params.poolId;
  s.priceE18 = event.params.priceE18;      // uint256 -> BigInt
  s.updatedAt = event.params.updatedAt;    // uint64  -> BigInt
  s.txHash = event.transaction.hash;
  s.blockNumber = event.block.number;
  s.save();
}
