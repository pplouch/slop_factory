class_name Fireball
extends Node3D
## A caster's ranged spell projectile (currently the only spell in the game:
## a fireball). Flies toward `target`'s *live* position -- a simple homing
## seek, not a physics body or a fire-and-forget straight line -- since the
## target may keep moving for the ~0.3-0.6s this is actually in flight, and
## detonates once close enough, applying `damage` to `target` via
## Combatant.take_damage and crediting `attacker` (the same (amount,
## attacker) contract every other damage source in this project already
## uses). Self-configuring and self-freeing, same as every other
## scripts/vfx/ object -- spawn it via Effects.spawn_fireball rather than
## instantiating scenes/fireball.tscn directly.
##
## `damage`/`attacker`/`target` must be set (by Effects.spawn_fireball)
## *before* this node enters the tree, since _ready() reads `target`
## immediately to seed its initial aim point.

const SPEED := 11.0
const HIT_DISTANCE := 0.4
const MAX_LIFETIME := 3.0
const FLIGHT_HEIGHT := 1.0

@export var damage: float = 0.0
@export var attacker: Node = null
@export var target: Node = null

var _aim_point: Vector3
var _life: float = 0.0


## Godot lifecycle hook: builds the glowing projectile visual and seeds the
## initial aim point from `target`'s position (falling back to this node's
## own spawn position if the target is already gone by the time this runs,
## which just makes the fireball fizzle in place next frame).
func _ready() -> void:
	_aim_point = target.global_position + Vector3(0.0, FLIGHT_HEIGHT, 0.0) if is_instance_valid(target) else global_position
	_build_visual()

## A small unshaded, emissive orange sphere plus a matching dim point light
## -- entirely code-built, like every other VFX primitive in this project
## (no hand-authored materials/assets).
func _build_visual() -> void:
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.55, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.35, 0.05)
	mat.emission_energy_multiplier = 2.5
	sphere.material = mat
	mesh_inst.mesh = sphere
	add_child(mesh_inst)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.15)
	light.light_energy = 1.4
	light.omni_range = 2.5
	add_child(light)

## Godot lifecycle hook: re-aims at `target`'s current position every frame
## and detonates once within HIT_DISTANCE of it, or after MAX_LIFETIME
## regardless -- covers the target dying or despawning mid-flight, so a
## fireball with nothing left to home in on still resolves instead of flying
## forever.
func _process(delta: float) -> void:
	_life += delta
	if is_instance_valid(target):
		_aim_point = target.global_position + Vector3(0.0, FLIGHT_HEIGHT, 0.0)

	var to_aim := _aim_point - global_position
	var dist := to_aim.length()
	if dist <= HIT_DISTANCE or _life > MAX_LIFETIME:
		_detonate()
		return

	global_position += (to_aim / dist) * SPEED * delta

## Applies damage (if the target is still around to receive it) and shows an
## impact burst, then frees this node. A target that died or despawned
## mid-flight just makes the fireball fizzle with no damage dealt -- there's
## nothing left to hit.
func _detonate() -> void:
	var burst_parent: Node = get_parent()
	if burst_parent:
		Effects.spawn_impact(burst_parent, global_position, Color(1.0, 0.5, 0.1), 14)
	if is_instance_valid(target) and damage > 0.0:
		target.take_damage(damage, attacker)
	queue_free()
