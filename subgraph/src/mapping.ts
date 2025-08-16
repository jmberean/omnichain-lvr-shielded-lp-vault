import { BigInt } from "@graphprotocol/graph-ts";
import { Signal as SignalEvent } from "../generated/LVRShieldHook/LVRShieldHook";
import { Signal } from "../generated/schema";

export function handleSignal(event: SignalEvent): void {
  const id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  const entity = new Signal(id);

  entity.poolId = event.params.poolId;
  entity.priceE18 = event.params.priceE18;
  // updatedAt in the ABI is uint64, but the generated type is BigInt already.
  entity.updatedAt = event.params.updatedAt;

  entity.blockNumber = event.block.number;
  entity.txHash = event.transaction.hash;

  entity.save();
}
