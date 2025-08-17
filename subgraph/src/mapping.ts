// subgraph/src/mapping.ts
import {
  ModeApplied as ModeAppliedEvent,
  LiquidityAction as LiquidityActionEvent,
} from "../generated/Vault/Vault";
import {
  ModeApplied as ModeAppliedEntity,
  LiquidityAction as LiquidityActionEntity,
} from "../generated/schema";

function entityId(txHash: string, logIndex: string): string {
  return txHash + "-" + logIndex;
}

export function handleModeApplied(ev: ModeAppliedEvent): void {
  const id = entityId(ev.transaction.hash.toHex(), ev.logIndex.toString());
  const ent = new ModeAppliedEntity(id);

  ent.poolId = ev.params.poolId;
  ent.mode = ev.params.mode;
  ent.epoch = ev.params.epoch;
  ent.reason = ev.params.reason;
  ent.centerTick = ev.params.centerTick;
  ent.halfWidthTicks = ev.params.halfWidthTicks;

  ent.blockNumber = ev.block.number;
  ent.blockTimestamp = ev.block.timestamp;
  ent.transactionHash = ev.transaction.hash;

  ent.save();
}

export function handleLiquidityAction(ev: LiquidityActionEvent): void {
  const id = entityId(ev.transaction.hash.toHex(), ev.logIndex.toString());
  const ent = new LiquidityActionEntity(id);

  ent.poolId = ev.params.poolId;
  ent.mode = ev.params.mode;
  ent.centerTick = ev.params.centerTick;
  ent.halfWidthTicks = ev.params.halfWidthTicks;
  ent.epoch = ev.params.epoch;
  ent.action = ev.params.action;

  ent.blockNumber = ev.block.number;
  ent.blockTimestamp = ev.block.timestamp;
  ent.transactionHash = ev.transaction.hash;

  ent.save();
}
