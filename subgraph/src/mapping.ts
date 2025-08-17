import {
  ModeApplied as ModeAppliedEvent,
  LiquidityAction as LiquidityActionEvent,
} from "../generated/Vault/Vault";
import { ModeApplied, LiquidityAction } from "../generated/schema";

export function handleModeApplied(event: ModeAppliedEvent): void {
  const id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  const e = new ModeApplied(id);
  e.poolId = event.params.poolId as Bytes;
  e.mode = event.params.mode;
  e.epoch = event.params.epoch;
  e.reason = event.params.reason;
  e.centerTick = event.params.centerTick;
  e.halfWidthTicks = event.params.halfWidthTicks;
  e.blockNumber = event.block.number;
  e.blockTimestamp = event.block.timestamp;
  e.transactionHash = event.transaction.hash;
  e.save();
}

export function handleLiquidityAction(event: LiquidityActionEvent): void {
  const id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  const e = new LiquidityAction(id);
  e.poolId = event.params.poolId as Bytes;
  e.mode = event.params.mode;
  e.epoch = event.params.epoch;
  e.action = event.params.action;
  e.centerTick = event.params.centerTick;
  e.halfWidthTicks = event.params.halfWidthTicks;
  e.blockNumber = event.block.number;
  e.blockTimestamp = event.block.timestamp;
  e.transactionHash = event.transaction.hash;
  e.save();
}
