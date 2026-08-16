class_name MovingState
extends BlobState
## Blob is walking toward `blob.move_target`.
##
## `blob.move_target` is a possibly-temporary waypoint -- Blob's stall-detour
## logic may redirect it sideways to route around an obstacle -- while
## `blob.final_target` is the real destination arrival is measured against.
## See blob.gd's `_update_stall_detection` for how the two stay in sync.
##
## Arriving at the final target hands off to HarvestingState if a resource
## node is queued up (Blob.pending_harvest_node), otherwise back to
## IdleState (a plain move-to-point order with nothing further to do).

## This state is a "travelling" state, so the stall-detector should watch it.
func is_travelling() -> bool:
	return true

## Steers the blob toward its current waypoint and checks for arrival at the
## final destination.
func physics_update(blob: CharacterBody3D, _delta: float) -> BlobState:
	blob._step_toward(blob.move_target)

	if blob.global_position.distance_to(blob.final_target) >= blob.ARRIVE_DISTANCE:
		return null

	blob.velocity = Vector3.ZERO
	if is_instance_valid(blob.pending_harvest_node) and blob.pending_harvest_node.amount > 0:
		return HarvestingState.new()

	blob.pending_harvest_node = null
	return IdleState.new()
