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
## final destination -- or, if a group order gave this blob some
## move_tolerance and it's stuck (another blob already standing on the
## exact point), accepts arriving nearby instead of circling forever.
func physics_update(blob: CharacterBody3D, _delta: float) -> BlobState:
	blob._step_toward(blob.move_target)

	var dist_to_target: float = blob.global_position.distance_to(blob.final_target)
	var close_enough_and_blocked: bool = (
		blob.move_tolerance > 0.0
		and dist_to_target < blob.ARRIVE_DISTANCE + blob.move_tolerance
		and blob._is_blocked_near_target()
	)
	if dist_to_target >= blob.ARRIVE_DISTANCE and not close_enough_and_blocked:
		return null

	blob.velocity = Vector3.ZERO
	if is_instance_valid(blob.pending_harvest_node) and blob.pending_harvest_node.amount > 0:
		return HarvestingState.new()

	blob.pending_harvest_node = null
	return IdleState.new()

## "Moving to harvest" if this leg of the trip ends at a resource node,
## otherwise a plain "Moving" (a direct move order with nothing queued up).
func display_name(blob: CharacterBody3D) -> String:
	if is_instance_valid(blob.pending_harvest_node):
		return "Moving to harvest"
	return "Moving"
