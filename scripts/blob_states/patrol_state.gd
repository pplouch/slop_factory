class_name PatrolState
extends BlobState
## Blob walks back and forth forever between two fixed points, until a
## fresh player order (move/harvest/another standing order) transitions it
## away -- there's no "done" condition, unlike MovingState.
##
## Holds both endpoints itself (rather than storing them on Blob) since
## they're private to this behavior; Blob.command_patrol just captures the
## blob's current position as `point_a` and passes the clicked point as
## `point_b`.

var point_a: Vector3
var point_b: Vector3
var _heading_to_b := true


func _init(p_point_a: Vector3, p_point_b: Vector3) -> void:
	point_a = p_point_a
	point_b = p_point_b

## Kicks off the first leg, heading toward point_b (point_a is normally
## wherever the blob already stood when the order was given).
func enter(blob: CharacterBody3D) -> void:
	_heading_to_b = true
	blob._set_destination(point_b)

func is_travelling() -> bool:
	return true

## Steers toward whichever endpoint is current; on arrival, flips to the
## other endpoint and keeps going (never transitions to another state).
func physics_update(blob: CharacterBody3D, _delta: float) -> BlobState:
	blob._step_toward(blob.move_target)
	if blob.global_position.distance_to(blob.final_target) >= blob.ARRIVE_DISTANCE:
		return null
	_heading_to_b = not _heading_to_b
	blob._set_destination(point_b if _heading_to_b else point_a)
	return null

func display_name(_blob: CharacterBody3D) -> String:
	return "Patrolling"
