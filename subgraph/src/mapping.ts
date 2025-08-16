import { ModeApplied as ModeAppliedEvent, LiquidityAction as LiquidityActionEvent } from "../generated/Vault/Vault";
import { ModeApplied, LiquidityAction } from "../generated/schema";

export function handleModeApplied(event: ModeAppliedEvent): void {
  const id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  const e = new ModeApplied(id);
  e.poolId = event.params.poolId;
  e.mode = event.params.mode;
  e.epoch = event.params.epoch;
  e.reason = event.params.reason;
  e.blockNumber = event.block.number;
  e.txHash = event.transaction.hash;
  e.save();
}

export function handleLiquidityAction(event: LiquidityActionEvent): void {
  const id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  const e = new LiquidityAction(id);
  e.poolId = event.params.poolId;
  e.mode = event.params.mode;
  e.epoch = event.params.epoch;
  e.baseDelta = event.params.baseDelta;
  e.quoteDelta = event.params.quoteDelta;
  e.reason = event.params.reason;
  e.blockNumber = event.block.number;
  e.txHash = event.transaction.hash;
  e.save();
}
