class_name ConstructState
extends BlobState
## Blob has arrived at an under-construction building and is contributing
## labor toward it every physics frame (scaled by blob.build_rate, itself
## driven by the blob's kind -- see BlobKinds.Kind.build_mult).
##
## Once the building disappears out from under it (demolished by the player
## mid-construction) or finishes, looks for another still-unfinished
## structure anywhere in the world and heads there next instead of always
## going idle (see Blob._next_build_or_idle) -- a blob given build duty
## keeps sweeping through every unfinished building until there's genuinely
## none left, only then falling back to IdleState.

## Periodic "hammering" feedback so standing still working on a building
## reads as active rather than just idling next to it.
const FEEDBACK_INTERVAL := 1.5
var _feedback_timer := 0.0


func physics_update(blob: CharacterBody3D, delta: float) -> BlobState:
	blob.velocity = Vector3.ZERO

	var building = blob.pending_build_target
	if not is_instance_valid(building) or not building.is_under_construction:
		blob.pending_build_target = null
		return blob._next_build_or_idle()

	building.add_construction_progress(delta * blob.build_rate)

	_feedback_timer -= delta
	if _feedback_timer <= 0.0:
		_feedback_timer = FEEDBACK_INTERVAL
		Effects.spawn_impact(blob.get_parent(), blob.global_position + Vector3(0.0, 0.6, 0.0), Color(0.9, 0.75, 0.4), 4)

	if not building.is_under_construction:
		blob.pending_build_target = null
		return blob._next_build_or_idle()
	return null

func display_name(_blob: CharacterBody3D) -> String:
	return "Constructing"
