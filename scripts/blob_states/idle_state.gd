class_name IdleState
extends BlobState
## Blob is standing still with nothing queued up.
##
## Never transitions on its own -- the only way out is a fresh player order
## (Blob.command_move / Blob.command_harvest), which transitions the blob
## directly into MovingState.

## Holds the blob at rest. No destination to walk toward, so just zero out
## any leftover velocity every frame.
func physics_update(blob: CharacterBody3D, _delta: float) -> BlobState:
	blob.velocity = Vector3.ZERO
	return null
