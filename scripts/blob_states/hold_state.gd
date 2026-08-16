class_name HoldState
extends BlobState
## Sentry duty: stands at a fixed anchor point, but -- unlike the passive
## auto-defense every blob always has (see Blob._update_combat, which only
## ever swings at whatever wanders into ATTACK_RANGE) -- actively closes in
## on anything that enters the wider DETECTION_RADIUS, then walks back to
## the anchor once the area's clear again. This is the one standing order
## that deliberately breaks the "a blob never chases" rule from Blob's file
## header, since "defend this spot" is the whole point of issuing it.

const DETECTION_RADIUS := 5.0
## Stop shy of the enemy's exact position -- Blob's own reactive combat
## (always running regardless of state) takes it from here once in range.
const ENGAGE_DISTANCE_FACTOR := 0.85

var anchor: Vector3
var _currently_moving := false


func _init(p_anchor: Vector3) -> void:
	anchor = p_anchor

func is_travelling() -> bool:
	return _currently_moving

## Each frame: chase the nearest enemy within DETECTION_RADIUS if one
## exists, otherwise head back to the anchor point, otherwise just stand
## guard. Never transitions itself -- only a fresh player order leaves this
## state.
func physics_update(blob: CharacterBody3D, _delta: float) -> BlobState:
	var enemy: Node = blob._find_nearest_enemy_in_range(DETECTION_RADIUS)
	if enemy and is_instance_valid(enemy):
		var to_enemy: Vector3 = enemy.global_position - blob.global_position
		to_enemy.y = 0.0
		if to_enemy.length() > blob.ATTACK_RANGE * ENGAGE_DISTANCE_FACTOR:
			_currently_moving = true
			blob._step_toward(enemy.global_position)
		else:
			_currently_moving = false
			blob.velocity = Vector3.ZERO
		return null

	if blob.global_position.distance_to(anchor) >= blob.ARRIVE_DISTANCE:
		_currently_moving = true
		blob._step_toward(anchor)
	else:
		_currently_moving = false
		blob.velocity = Vector3.ZERO
	return null

func display_name(_blob: CharacterBody3D) -> String:
	return "Holding position"
