import { ModeApplied as ModeAppliedEvent, LiquidityAction as LiquidityActionEvent } from "../generated/Vault/Vault"
import { ModeApplied, LiquidityAction } from "../generated/schema"

export function handleModeApplied(event: ModeAppliedEvent): void {
  let entity = new ModeApplied(event.transaction.hash.toHex() + "-" + event.logIndex.toString())
  entity.poolId = event.params.poolId
  entity.mode = event.params.mode
  entity.epoch = event.params.epoch
  entity.reason = event.params.reason
  entity.centerTick = event.params.centerTick
  entity.halfWidthTicks = event.params.halfWidthTicks
  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash
  entity.save()
}

export function handleLiquidityAction(event: LiquidityActionEvent): void {
  let entity = new LiquidityAction(event.transaction.hash.toHex() + "-" + event.logIndex.toString())
  entity.poolId = event.params.poolId
  entity.mode = event.params.mode
  entity.centerTick = event.params.centerTick
  entity.halfWidthTicks = event.params.halfWidthTicks
  entity.epoch = event.params.epoch
  entity.action = event.params.action
  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash
  entity.save()
}