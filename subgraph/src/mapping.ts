import { BigDecimal } from "@graphprotocol/graph-ts";
import { ModeApplied as VaultModeApplied } from "../abis/LVRVault/LVRVault";
import { ModeChange } from "../generated/schema";

export function handleVaultModeApplied(ev: VaultModeApplied): void {
  const id = ev.transaction.hash.concatI32(ev.logIndex.toI32()).toHex();
  const m = new ModeChange(id);
  m.pool = ev.params.poolId; // bytes32
  m.oldMode = "NA";
  m.newMode = ev.params.newMode;
  m.timestamp = ev.block.timestamp;
  m.lvrThreshold = BigDecimal.zero();
  m.txHash = ev.transaction.hash;
  m.blockNumber = ev.block.number;
  m.save();
}
