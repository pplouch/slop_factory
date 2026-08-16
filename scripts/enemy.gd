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

@onready var _blob_body: Node3D = $Visuals/BlobBody
@onready var _blob_mesh: MeshInstance3D = $Visuals/BlobBody/Body

@onready var _quad_body: Node3D = $Visuals/QuadrupedBody
@onready var _quad_leg_fl: Node3D = $Visuals/QuadrupedBody/FrontLeftLegPivot
@onready var _quad_leg_fr: Node3D = $Visuals/QuadrupedBody/FrontRightLegPivot
@onready var _quad_leg_bl: Node3D = $Visuals/QuadrupedBody/BackLeftLegPivot
@onready var _quad_leg_br: Node3D = $Visuals/QuadrupedBody/BackRightLegPivot
@onready var _quad_meshes: Array = [
	$Visuals/QuadrupedBody/Torso, $Visuals/QuadrupedBody/Head, $Visuals/QuadrupedBody/Tail,
	$Visuals/QuadrupedBody/FrontLeftLegPivot/FrontLeftLeg, $Visuals/QuadrupedBody/FrontRightLegPivot/FrontRightLeg,
	$Visuals/QuadrupedBody/BackLeftLegPivot/BackLeftLeg, $Visuals/QuadrupedBody/BackRightLegPivot/BackRightLeg,
]

@onready var _hum_body: Node3D = $Visuals/HumanoidBody
@onready var _hum_left_arm_pivot: Node3D = $Visuals/HumanoidBody/LeftArmPivot
@onready var _hum_right_arm_pivot: Node3D = $Visuals/HumanoidBody/RightArmPivot
@onready var _hum_left_leg_pivot: Node3D = $Visuals/HumanoidBody/LeftLegPivot
@onready var _hum_right_leg_pivot: Node3D = $Visuals/HumanoidBody/RightLegPivot
@onready var _hum_meshes: Array = [
	$Visuals/HumanoidBody/Torso, $Visuals/HumanoidBody/Head,
	$Visuals/HumanoidBody/LeftArmPivot/LeftArm, $Visuals/HumanoidBody/RightArmPivot/RightArm,
	$Visuals/HumanoidBody/LeftLegPivot/LeftLeg, $Visuals/HumanoidBody/RightLegPivot/RightLeg,
]

## Which of the three pre-built rigs (see Enemy.tscn) this kind uses -- set
## once in _apply_kind_look from EnemyKinds.Kind.body_type.
var _body_type: String = "blob"
## Shared per-instance material every visible-rig mesh points at (see
## _apply_kind_look) -- kept as a field so the damage/animation code never
## needs to know which rig is active to recolor/read it.
var _body_material: StandardMaterial3D
## Gait-cycle phase accumulator driving the walk animation (see
## _update_limb_animation) -- mirrors Blob's own approach exactly.
var _gait_phase: float = 0.0
## Counts down while a one-off attack animation is playing, so the regular
## walk animation doesn't fight it every frame.
var _attack_swing_timer: float = 0.0

const GAIT_CYCLES_PER_SECOND := 1.5
const GAIT_AMPLITUDE := 0.55
const ATTACK_SWING_DURATION := 0.22
const LIMB_RESET_SPEED := 8.0


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

## Shows only the one rig (see Enemy.tscn: BlobBody/QuadrupedBody/
## HumanoidBody) matching this kind's EnemyKinds.body_type, tints every
## mesh in that rig with one shared duplicated material (the same
## "duplicate so only this instance is recolored" approach Blob uses), and
## scales the cosmetic Visuals node -- never this CharacterBody3D's own
## root, since scaling a dynamic physics body directly produces a
## transform Jolt can't simulate correctly (see CLAUDE.md).
func _apply_kind_look(kind: EnemyKinds.Kind) -> void:
	_body_type = kind.body_type
	_blob_body.visible = _body_type == "blob"
	_quad_body.visible = _body_type == "quadruped"
	_hum_body.visible = _body_type == "humanoid"

	var meshes: Array = _blob_meshes_for_type()
	_body_material = meshes[0].mesh.material.duplicate()
	_body_material.albedo_color = Color.from_hsv(kind.hue, 0.55, 0.35 if kind.hue == 0.0 else 0.6)
	for mesh_inst in meshes:
		mesh_inst.set_surface_override_material(0, _body_material)

	_visuals.scale = Vector3.ONE * kind.body_scale

## The tintable mesh list for whichever rig is currently active.
func _blob_meshes_for_type() -> Array:
	match _body_type:
		"quadruped":
			return _quad_meshes
		"humanoid":
			return _hum_meshes
		_:
			return [_blob_mesh]

## Godot physics tick: chases and fights the nearest blob in detection
## range, or wanders near home if none are close, then runs shared regen
## and the limb/body animation matching whichever rig is active.
func _physics_process(delta: float) -> void:
	var target_blob := _find_nearest_blob_in_range(DETECTION_RANGE)
	if target_blob:
		_chase_and_attack(target_blob, delta)
	else:
		_wander(delta)
	move_and_slide()
	global_position.y = 0.0
	_update_combat_regen(delta)
	_update_limb_animation(delta)

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
		_play_attack_animation()

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

## Drives whichever rig is currently visible every physics frame: a walk
## cycle while actually moving (wandering or chasing both count -- only the
## speed differs), and an easing return to neutral otherwise (standing
## still mid-attack-cooldown, or between wander picks). A one-off attack
## animation (see _play_attack_animation) takes over for its short
## duration instead of fighting this.
func _update_limb_animation(delta: float) -> void:
	if _attack_swing_timer > 0.0:
		_attack_swing_timer -= delta
		return

	var speed: float = velocity.length()
	var is_moving: bool = speed > 0.15

	match _body_type:
		"quadruped":
			_update_quadruped_gait(delta, is_moving, speed)
		"humanoid":
			_update_humanoid_gait(delta, is_moving, speed)
		_:
			_update_blob_bounce(delta, is_moving, speed)

## Diagonal-pair gait (front-left+back-right swing together, front-right+
## back-left the other way), the classic four-legged walk cycle.
func _update_quadruped_gait(delta: float, is_moving: bool, speed: float) -> void:
	if is_moving:
		_gait_phase += delta * TAU * GAIT_CYCLES_PER_SECOND * (speed / max(move_speed, 0.01))
		var swing := sin(_gait_phase) * GAIT_AMPLITUDE
		_quad_leg_fl.rotation.x = swing
		_quad_leg_br.rotation.x = swing
		_quad_leg_fr.rotation.x = -swing
		_quad_leg_bl.rotation.x = -swing
	else:
		_quad_leg_fl.rotation.x = lerp(_quad_leg_fl.rotation.x, 0.0, delta * LIMB_RESET_SPEED)
		_quad_leg_fr.rotation.x = lerp(_quad_leg_fr.rotation.x, 0.0, delta * LIMB_RESET_SPEED)
		_quad_leg_bl.rotation.x = lerp(_quad_leg_bl.rotation.x, 0.0, delta * LIMB_RESET_SPEED)
		_quad_leg_br.rotation.x = lerp(_quad_leg_br.rotation.x, 0.0, delta * LIMB_RESET_SPEED)

## Same opposite arm/leg swing Blob uses for its own humanoid rig.
func _update_humanoid_gait(delta: float, is_moving: bool, speed: float) -> void:
	if is_moving:
		_gait_phase += delta * TAU * GAIT_CYCLES_PER_SECOND * (speed / max(move_speed, 0.01))
		var swing := sin(_gait_phase) * GAIT_AMPLITUDE
		_hum_left_arm_pivot.rotation.x = swing
		_hum_right_arm_pivot.rotation.x = -swing
		_hum_left_leg_pivot.rotation.x = -swing
		_hum_right_leg_pivot.rotation.x = swing
	else:
		_hum_left_arm_pivot.rotation.x = lerp(_hum_left_arm_pivot.rotation.x, 0.0, delta * LIMB_RESET_SPEED)
		_hum_right_arm_pivot.rotation.x = lerp(_hum_right_arm_pivot.rotation.x, 0.0, delta * LIMB_RESET_SPEED)
		_hum_left_leg_pivot.rotation.x = lerp(_hum_left_leg_pivot.rotation.x, 0.0, delta * LIMB_RESET_SPEED)
		_hum_right_leg_pivot.rotation.x = lerp(_hum_right_leg_pivot.rotation.x, 0.0, delta * LIMB_RESET_SPEED)

## No limbs to swing on the amorphous blob rig -- a squash/stretch bounce
## while moving instead, easing back to a neutral scale otherwise.
func _update_blob_bounce(delta: float, is_moving: bool, speed: float) -> void:
	if is_moving:
		_gait_phase += delta * TAU * GAIT_CYCLES_PER_SECOND * 2.0 * (speed / max(move_speed, 0.01))
		var squash: float = sin(_gait_phase) * 0.12
		_blob_mesh.scale = Vector3(1.0 - squash * 0.5, 0.9 + squash, 1.0 - squash * 0.5)
	else:
		_blob_mesh.scale = _blob_mesh.scale.lerp(Vector3(1.0, 0.9, 1.0), delta * LIMB_RESET_SPEED)

## Plays a one-off attack animation matching whichever rig is active,
## taking over from the regular walk/bounce animation for
## ATTACK_SWING_DURATION so the two don't fight: a forward punch for the
## humanoid rig (mirrors Blob's own _play_attack_swing), a quick lunge/dip
## for the quadruped rig (like a bite), and a sharp squash-lunge for the
## amorphous blob rig.
func _play_attack_animation() -> void:
	_attack_swing_timer = ATTACK_SWING_DURATION
	var tween := create_tween()
	match _body_type:
		"quadruped":
			tween.tween_property(_quad_body, "rotation:x", -0.35, ATTACK_SWING_DURATION * 0.4) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(_quad_body, "rotation:x", 0.0, ATTACK_SWING_DURATION * 0.6) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		"humanoid":
			tween.tween_property(_hum_right_arm_pivot, "rotation:x", -1.1, ATTACK_SWING_DURATION * 0.4) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(_hum_right_arm_pivot, "rotation:x", 0.0, ATTACK_SWING_DURATION * 0.6) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_:
			tween.tween_property(_blob_mesh, "scale", Vector3(1.25, 0.65, 1.25), ATTACK_SWING_DURATION * 0.4) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(_blob_mesh, "scale", Vector3(1.0, 0.9, 1.0), ATTACK_SWING_DURATION * 0.6) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
