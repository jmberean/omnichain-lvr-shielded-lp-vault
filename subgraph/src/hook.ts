import { AdminApplyModeForDemo as AdminEvent } from "../generated/Hook/Hook";
import { AdminAction } from "../generated/schema";
import { Bytes } from "@graphprotocol/graph-ts";

export function handleAdminApplyModeForDemo(ev: AdminEvent): void {
  const id = ev.transaction.hash.toHex() + "-" + ev.logIndex.toString();
  const ent = new AdminAction(id);

  ent.poolId = ev.params.poolId as Bytes;
  ent.mode = ev.params.mode;
  ent.epoch = ev.params.epoch;
  ent.reason = ev.params.reason;

  ent.blockNumber = ev.block.number;
  ent.timestamp = ev.block.timestamp;
  ent.txHash = ev.transaction.hash;
  ent.hook = ev.address;

  ent.save();
}
