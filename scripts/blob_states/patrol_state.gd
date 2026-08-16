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
## See Blob.move_tolerance -- reapplied after every leg's _set_destination
## call, since that resets it to 0 by default (point_b is typically shared
## across a whole squad, so without this every blob but the first would be
## stuck circling it forever once it's occupied).
var move_tolerance: float
var _heading_to_b := true


func _init(p_point_a: Vector3, p_point_b: Vector3, p_move_tolerance: float = 0.0) -> void:
	point_a = p_point_a
	point_b = p_point_b
	move_tolerance = p_move_tolerance

## Kicks off the first leg, heading toward point_b (point_a is normally
## wherever the blob already stood when the order was given).
func enter(blob: CharacterBody3D) -> void:
	_heading_to_b = true
	blob._set_destination(point_b)
	blob.move_tolerance = move_tolerance

func is_travelling() -> bool:
	return true

## Steers toward whichever endpoint is current; on arrival (or close enough
## while stuck, see Blob.move_tolerance), flips to the other endpoint and
## keeps going (never transitions to another state).
func physics_update(blob: CharacterBody3D, _delta: float) -> BlobState:
	blob._step_toward(blob.move_target)

	var dist_to_target: float = blob.global_position.distance_to(blob.final_target)
	var close_enough_and_blocked: bool = (
		move_tolerance > 0.0
		and dist_to_target < blob.ARRIVE_DISTANCE + move_tolerance
		and blob._is_blocked_near_target()
	)
	if dist_to_target >= blob.ARRIVE_DISTANCE and not close_enough_and_blocked:
		return null

	_heading_to_b = not _heading_to_b
	blob._set_destination(point_b if _heading_to_b else point_a)
	blob.move_tolerance = move_tolerance
	return null

func display_name(_blob: CharacterBody3D) -> String:
	return "Patrolling"
