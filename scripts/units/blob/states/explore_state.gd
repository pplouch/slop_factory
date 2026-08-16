class_name ExploreState
extends BlobState
## Wanders forever within a radius of the point the order was issued from,
## pausing briefly between legs -- same spirit as Enemy's idle wander, but
## as a standing order a blob stays in until a fresh player command
## transitions it away, rather than a fallback with no player-facing name.

const EXPLORE_RADIUS := 10.0
const PAUSE_RANGE := Vector2(1.0, 3.0)

var anchor: Vector3
var _paused := false
var _pause_timer := 0.0


func _init(p_anchor: Vector3) -> void:
	anchor = p_anchor

## Picks the first random destination.
func enter(blob: CharacterBody3D) -> void:
	_pick_new_target(blob)

## Not travelling during the deliberate pause between legs -- otherwise the
## stall-detector would mistake "standing still on purpose" for being stuck
## and kick off a pointless sideways detour.
func is_travelling() -> bool:
	return not _paused

func physics_update(blob: CharacterBody3D, delta: float) -> BlobState:
	if _paused:
		blob.velocity = Vector3.ZERO
		_pause_timer -= delta
		if _pause_timer <= 0.0:
			_pick_new_target(blob)
		return null

	blob._step_toward(blob.move_target)
	if blob.global_position.distance_to(blob.final_target) >= blob.ARRIVE_DISTANCE:
		return null

	blob.velocity = Vector3.ZERO
	_paused = true
	_pause_timer = randf_range(PAUSE_RANGE.x, PAUSE_RANGE.y)
	return null

## Picks a new random point within EXPLORE_RADIUS of `anchor` and heads
## there, ending the pause.
func _pick_new_target(blob: CharacterBody3D) -> void:
	_paused = false
	var angle := randf() * TAU
	var r := sqrt(randf()) * EXPLORE_RADIUS
	var target := anchor + Vector3(cos(angle) * r, 0.0, sin(angle) * r)
	blob._set_destination(target)

func display_name(_blob: CharacterBody3D) -> String:
	return "Exploring"
