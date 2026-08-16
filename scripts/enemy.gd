class_name Enemy
extends Combatant
## The map's hostile creatures: wander near their spawn point, and once a
## blob comes within DETECTION_RANGE, close in and trade blows with it
## until one of them dies or the blob moves back out of range. Health/
## damage/regen math is inherited from Combatant; this file adds movement/
## attack-timing behavior shared by every kind, with EnemyKinds supplying
## the per-kind stat multipliers and look (mirrors Blob/BlobKinds exactly).

const MOVE_SPEED := 2.6
const DETECTION_RANGE := 9.0
const ATTACK_RANGE := 1.3
const WANDER_INTERVAL_RANGE := Vector2(2.0, 5.0)
const WANDER_RADIUS := 6.0

const BASE_MAX_HEALTH := 18.0
const BASE_HEALTH_REGEN := 0.5
const BASE_DEXTERITY := 0.6
const BASE_ATTACK_POWER := 3.0
const BASE_ATTACK_INTERVAL := 1.4

## Which EnemyKinds archetype this is. Must be set (by whoever instantiates
## the scene, e.g. World's biome-aware spawner) *before* this node enters
## the tree, since _ready() reads it immediately to pick stats and cosmetics.
@export var kind_id: String = "slime"

var attack_power: float = BASE_ATTACK_POWER
var attack_interval: float = BASE_ATTACK_INTERVAL
var move_speed: float = MOVE_SPEED

## The point wandering is centered on (its spawn position), so a lone enemy
## roams a local patch instead of drifting arbitrarily far over time.
var _home: Vector3 = Vector3.ZERO
var _wander_target: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0
var _attack_cooldown: float = 0.0

@onready var _visuals: Node3D = $Visuals
@onready var _body_mesh: MeshInstance3D = $Visuals/Body


## Godot lifecycle hook: sets starting stats (scaled by both the current
## difficulty ramp -- see GameManager.get_enemy_difficulty_multiplier, so
## enemies spawned early in a session are noticeably weaker than ones
## spawned later -- and this instance's EnemyKinds multipliers), applies
## its kind's look, and registers for lookup by Blob's combat scan (see
## Blob._find_nearest_enemy_in_range).
func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	var kind := EnemyKinds.get_kind(kind_id)
	var difficulty := GameManager.get_enemy_difficulty_multiplier()
	max_health = BASE_MAX_HEALTH * difficulty * kind.health_mult
	health = max_health
	health_regen = BASE_HEALTH_REGEN
	dexterity = BASE_DEXTERITY
	attack_power = BASE_ATTACK_POWER * difficulty * kind.attack_mult
	move_speed = MOVE_SPEED * kind.speed_mult
	_apply_kind_look(kind)
	_home = global_position
	_pick_new_wander_target()

## Tints and scales this enemy according to its EnemyKinds archetype, the
## same "duplicate the shared material so only this instance is recolored"
## approach Blob uses for its own per-kind look. Scales the cosmetic
## Visuals node, never this CharacterBody3D's own root -- scaling a
## dynamic physics body directly produces a transform Jolt can't simulate
## correctly (see CLAUDE.md).
func _apply_kind_look(kind: EnemyKinds.Kind) -> void:
	var mat: StandardMaterial3D = _body_mesh.mesh.material.duplicate()
	mat.albedo_color = Color.from_hsv(kind.hue, 0.55, 0.35 if kind.hue == 0.0 else 0.6)
	_body_mesh.set_surface_override_material(0, mat)
	_visuals.scale = Vector3.ONE * kind.body_scale

## Godot physics tick: chases and fights the nearest blob in detection
## range, or wanders near home if none are close, then runs shared regen.
func _physics_process(delta: float) -> void:
	var target_blob := _find_nearest_blob_in_range(DETECTION_RANGE)
	if target_blob:
		_chase_and_attack(target_blob, delta)
	else:
		_wander(delta)
	move_and_slide()
	global_position.y = 0.0
	_update_combat_regen(delta)

## Closest member of the "blobs" group within `range_limit`, or null.
func _find_nearest_blob_in_range(range_limit: float) -> Node:
	var nearest: Node = null
	var nearest_dist := range_limit
	for blob in get_tree().get_nodes_in_group("blobs"):
		if not is_instance_valid(blob):
			continue
		var d := global_position.distance_to(blob.global_position)
		if d <= nearest_dist:
			nearest_dist = d
			nearest = blob
	return nearest

## Closes distance to `blob` if outside melee range, otherwise stops and
## attacks it on this enemy's own attack-interval timer.
func _chase_and_attack(blob: Node, delta: float) -> void:
	_note_combat_activity()
	_attack_cooldown = max(0.0, _attack_cooldown - delta)

	var to_blob: Vector3 = blob.global_position - global_position
	to_blob.y = 0.0
	var dist := to_blob.length()

	if dist > ATTACK_RANGE:
		var dir := to_blob.normalized()
		velocity = dir * move_speed
		look_at(global_position + dir, Vector3.UP)
		return

	velocity = Vector3.ZERO
	if _attack_cooldown <= 0.0:
		_attack_cooldown = attack_interval
		blob.take_damage(attack_power, self)

## Idles toward a slowly-changing random point near home when no blob is
## nearby, so the enemy reads as "patrolling" rather than a frozen statue.
func _wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0 or global_position.distance_to(_wander_target) < 0.5:
		_pick_new_wander_target()

	var to_target := _wander_target - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	if dist > 0.1:
		var dir := to_target.normalized()
		velocity = dir * move_speed * 0.5
		look_at(global_position + dir, Vector3.UP)
	else:
		velocity = Vector3.ZERO

## Picks a new wander destination within WANDER_RADIUS of home and resets
## the timer that forces picking another one even if this one is never
## quite reached (e.g. stuck against terrain).
func _pick_new_wander_target() -> void:
	var angle := randf() * TAU
	var r := randf() * WANDER_RADIUS
	_wander_target = _home + Vector3(cos(angle) * r, 0.0, sin(angle) * r)
	_wander_timer = randf_range(WANDER_INTERVAL_RANGE.x, WANDER_INTERVAL_RANGE.y)
