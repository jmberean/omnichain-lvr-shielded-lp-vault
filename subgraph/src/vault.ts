import { ModeApplied as ModeAppliedEvent } from "../generated/Vault/Vault";
import { ModeApplied } from "../generated/schema";
import { Bytes, crypto } from "@graphprotocol/graph-ts";

export function handleModeApplied(ev: ModeAppliedEvent): void {
  // id = txHash-logIndex
  const id = ev.transaction.hash.toHex() + "-" + ev.logIndex.toString();
  const ent = new ModeApplied(id);

  ent.poolId = ev.params.poolId as Bytes;
  ent.mode = ev.params.mode;
  ent.epoch = ev.params.epoch;
  ent.reason = ev.params.reason;
  ent.centerTick = ev.params.centerTick;
  ent.halfWidthTicks = ev.params.halfWidthTicks;

  ent.blockNumber = ev.block.number;
  ent.timestamp = ev.block.timestamp;
  ent.txHash = ev.transaction.hash;
  ent.vault = ev.address;

  ent.save();
}
