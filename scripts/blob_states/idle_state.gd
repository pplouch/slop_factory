class_name IdleState
extends BlobState
## Blob is standing still with nothing queued up.
##
## Never transitions on its own -- the only way out is a fresh player order
## (Blob.command_move / command_harvest / a standing order), which
## transitions the blob directly into another state.
##
## Purely cosmetic "living creature" flavor layered on top of that: every
## few seconds, either takes a couple of steps to a small nearby point, or
## -- if another idle blob happens to be close by -- turns to face it and
## chirps, a lightweight stand-in for "units interacting with each other"
## rather than a full social simulation. Neither ever leaves IdleState;
## both are just velocity nudges on top of "otherwise stand still".

const FIDGET_INTERVAL_RANGE := Vector2(4.0, 9.0)
const FIDGET_WANDER_RADIUS := 1.5
const FIDGET_WANDER_SPEED_FACTOR := 0.4
const FIDGET_MAX_DURATION := 2.0
const GREET_RADIUS := 3.0

var _fidget_timer := randf_range(FIDGET_INTERVAL_RANGE.x, FIDGET_INTERVAL_RANGE.y)
var _fidgeting := false
var _fidget_target: Vector3 = Vector3.ZERO
var _fidget_duration := 0.0


func physics_update(blob: CharacterBody3D, delta: float) -> BlobState:
	if _fidgeting:
		_step_fidget(blob, delta)
		return null

	blob.velocity = Vector3.ZERO
	_fidget_timer -= delta
	if _fidget_timer <= 0.0:
		_fidget_timer = randf_range(FIDGET_INTERVAL_RANGE.x, FIDGET_INTERVAL_RANGE.y)
		_start_fidget(blob)
	return null

## Walks toward the current fidget target at a slow crawl until reached or
## the duration runs out, whichever comes first.
func _step_fidget(blob: CharacterBody3D, delta: float) -> void:
	_fidget_duration -= delta
	var to_target: Vector3 = _fidget_target - blob.global_position
	to_target.y = 0.0
	if _fidget_duration <= 0.0 or to_target.length() < 0.15:
		_fidgeting = false
		blob.velocity = Vector3.ZERO
		return
	var dir := to_target.normalized()
	blob.velocity = dir * blob.speed * FIDGET_WANDER_SPEED_FACTOR
	blob.look_at(blob.global_position + dir, Vector3.UP)

## Picks this idle period's fidget: greet a nearby idle blob (turn to face
## it, chirp) if one's close enough, otherwise wander a couple of steps to
## a small random nearby point.
func _start_fidget(blob: CharacterBody3D) -> void:
	var neighbor := _find_nearby_idle_blob(blob)
	if neighbor and randf() < 0.5:
		var to_neighbor: Vector3 = neighbor.global_position - blob.global_position
		to_neighbor.y = 0.0
		if to_neighbor.length() > 0.05:
			blob.look_at(blob.global_position + to_neighbor, Vector3.UP)
		Effects.play_chirp(blob.get_parent(), blob.global_position + Vector3(0.0, 0.6, 0.0), 0.3)
		return

	var angle := randf() * TAU
	var r := randf() * FIDGET_WANDER_RADIUS
	_fidget_target = blob.global_position + Vector3(cos(angle) * r, 0.0, sin(angle) * r)
	_fidget_duration = FIDGET_MAX_DURATION
	_fidgeting = true

## Closest other idle blob within GREET_RADIUS, or null.
func _find_nearby_idle_blob(blob: CharacterBody3D) -> Node:
	for other in blob.get_tree().get_nodes_in_group("blobs"):
		if other == blob or not is_instance_valid(other):
			continue
		if not (other.current_state is IdleState):
			continue
		if blob.global_position.distance_to(other.global_position) <= GREET_RADIUS:
			return other
	return null

func display_name(_blob: CharacterBody3D) -> String:
	return "Idle"
