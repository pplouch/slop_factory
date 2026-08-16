class_name ReturningState
extends BlobState
## Blob is hauling its inventory back to the nearest building's SpawnPoint to
## deposit it.
##
## Arriving triggers the deposit (Blob._deposit), which itself decides the
## next state: back to MovingState if there's still more to harvest at the
## same node, or IdleState if the job is done.

## This state is a "travelling" state, so the stall-detector should watch it.
func is_travelling() -> bool:
	return true

## Steers the blob toward the deposit point and hands off to the deposit
## logic once it arrives.
func physics_update(blob: CharacterBody3D, _delta: float) -> BlobState:
	blob._step_toward(blob.move_target)

	if blob.global_position.distance_to(blob.final_target) >= blob.ARRIVE_DISTANCE + 0.5:
		return null

	blob.velocity = Vector3.ZERO
	return blob._deposit()
