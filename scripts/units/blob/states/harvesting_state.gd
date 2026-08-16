class_name HarvestingState
extends BlobState
## Blob has arrived at a resource node and is working it once every
## `blob.harvest_interval` seconds, stashing the yield in its inventory.
##
## Leaves for ReturningState once the blob's inventory is full or the node
## runs dry, or falls back to IdleState if the node disappears out from
## under it (e.g. depleted by another blob a moment earlier).

## Seconds accumulated toward the next harvest tick. Lives on the state
## instance (not on Blob) since it's only meaningful while harvesting.
var _accumulated_time := 0.0

## Reset the tick timer whenever this state becomes active, so resuming a
## harvest (e.g. after a deposit trip) doesn't inherit a stale timer.
func enter(_blob: CharacterBody3D) -> void:
	_accumulated_time = 0.0

## Ticks the harvest timer, pulls yield from the resource node when it fires,
## and decides whether the blob should keep chopping, head home, or give up.
func physics_update(blob: CharacterBody3D, delta: float) -> BlobState:
	blob.velocity = Vector3.ZERO

	if not is_instance_valid(blob.pending_harvest_node) or blob.pending_harvest_node.amount <= 0:
		blob.pending_harvest_node = null
		return IdleState.new()

	_accumulated_time += delta
	if _accumulated_time < blob.harvest_interval:
		return null
	_accumulated_time = 0.0

	var node = blob.pending_harvest_node
	var taken: int = node.harvest(blob.harvest_amount)
	if taken > 0:
		blob._collect(node.resource_type, taken, node.global_position)

	if blob._inventory_total() >= blob.carry_capacity or node.amount <= 0:
		return blob._start_returning_trip()
	return null

func display_name(_blob: CharacterBody3D) -> String:
	return "Harvesting"
