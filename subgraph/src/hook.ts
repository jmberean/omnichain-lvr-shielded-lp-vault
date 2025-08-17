import { Signal as SignalEvent, ModeChanged as ModeChangedEvent, HomeRecorded as HomeRecordedEvent } from "../generated/LVRShieldHook/LVRShieldHook"
import { Signal, ModeChanged, HomeRecorded } from "../generated/schema"

export function handleSignal(event: SignalEvent): void {
  let entity = new Signal(event.transaction.hash.toHex() + "-" + event.logIndex.toString())
  entity.poolId = event.params.poolId
  entity.spotTick = event.params.spotTick
  entity.ewmaTick = event.params.ewmaTick
  entity.sigmaTicks = event.params.sigmaTicks
  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash
  entity.save()
}

export function handleModeChanged(event: ModeChangedEvent): void {
  let entity = new ModeChanged(event.transaction.hash.toHex() + "-" + event.logIndex.toString())
  entity.poolId = event.params.poolId
  entity.oldMode = event.params.oldMode
  entity.newMode = event.params.newMode
  entity.epoch = event.params.epoch
  entity.reason = event.params.reason
  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash
  entity.save()
}

export function handleHomeRecorded(event: HomeRecordedEvent): void {
  let entity = new HomeRecorded(event.transaction.hash.toHex() + "-" + event.logIndex.toString())
  entity.poolId = event.params.poolId
  entity.centerTick = event.params.centerTick
  entity.halfWidthTicks = event.params.halfWidthTicks
  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash
  entity.save()
}