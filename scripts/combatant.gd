class_name Combatant
extends CharacterBody3D
## Shared combat chassis for anything that can fight and take damage (Blob,
## Enemy). Owns health/regen and the damage-resolution math (a defender's
## dexterity gives it a chance to evade an incoming hit); subclasses provide
## their own attack behavior/timing and can override _on_death() for
## kind-specific death handling.
##
## Pulled out as a real base class (rather than duplicated in both Blob and
## Enemy) since the health/damage/evasion math is identical for both --
## only *how* and *when* each side attacks differs, and that stays in the
## subclasses.

const COMBAT_MEMORY_TIME := 4.0
const EVASION_PER_DEXTERITY := 0.06
const MAX_EVASION_CHANCE := 0.35

# -- Health bar geometry (see _build_health_bar) --
const HEALTH_BAR_WIDTH := 0.8
const HEALTH_BAR_HEIGHT := 0.12
const HEALTH_BAR_Y := 0.15

var max_health: float = 10.0
var health: float = 10.0
var health_regen: float = 0.0
var dexterity: float = 1.0

## Seconds since this combatant last landed or received a hit. Regen only
## kicks in once this exceeds COMBAT_MEMORY_TIME, so it doesn't visibly tick
## up mid-fight.
var _time_since_combat: float = COMBAT_MEMORY_TIME + 1.0

## The scaled child whose scale.x drives the visible fill width (see
## _build_health_bar for how its pivot position makes it shrink from the
## left edge rather than from its center).
var _health_bar_fill_pivot: Node3D


## Godot lifecycle hook: builds the small billboarded health bar shown at
## this combatant's feet. Blob and Enemy both call `super._ready()` first
## thing so it exists before their own kind-specific setup runs.
func _ready() -> void:
	_build_health_bar()

## Builds a two-quad billboarded health bar (dark background + green fill)
## entirely in code, positioned near the ground ("under the unit" rather
## than floating over its head) -- built once here rather than duplicated
## across Blob.tscn/Enemy.tscn so both kinds get it for free.
##
## The fill quad is a child of a pivot offset to the bar's left edge, so
## scaling the pivot's scale.x (see _refresh_health_bar) shrinks the fill
## toward that left edge instead of toward the bar's center -- the usual
## "health bar drains right-to-left" look.
func _build_health_bar() -> void:
	var root := Node3D.new()
	root.position = Vector3(0.0, HEALTH_BAR_Y, 0.0)
	add_child(root)

	var bg := MeshInstance3D.new()
	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# Billboard mode reorients the quad in the vertex shader, which can leave
	# its original front face pointed away from the camera depending on view
	# angle -- disable culling so it's never invisible from the "wrong" side.
	bg_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Sitting this low, the unit's own body (or terrain) would otherwise
	# constantly poke in front of the bar depth-wise from a top-down camera
	# -- ignore the depth buffer so it always draws on top, the same trick
	# used for most in-game UI billboards.
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 1
	bg_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.85)
	bg_mesh.material = bg_mat
	bg.mesh = bg_mesh
	root.add_child(bg)

	_health_bar_fill_pivot = Node3D.new()
	_health_bar_fill_pivot.position = Vector3(-HEALTH_BAR_WIDTH * 0.5, 0.0, 0.002)
	root.add_child(_health_bar_fill_pivot)

	var fill := MeshInstance3D.new()
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fill_mat.no_depth_test = true
	fill_mat.render_priority = 2
	fill_mat.albedo_color = Color(0.3, 0.9, 0.35, 1.0)
	fill_mesh.material = fill_mat
	fill.mesh = fill_mesh
	fill.position = Vector3(HEALTH_BAR_WIDTH * 0.5, 0.0, 0.0)
	_health_bar_fill_pivot.add_child(fill)

## Rescales the fill pivot to match the current health fraction. Called
## every frame from _update_combat_regen so the bar stays live whether
## health just changed from damage or from passive regen.
func _refresh_health_bar() -> void:
	if _health_bar_fill_pivot:
		_health_bar_fill_pivot.scale.x = clamp(health / max_health, 0.0, 1.0) if max_health > 0.0 else 0.0

## Called every physics frame by a subclass: ages out the combat-memory
## timer, applies regen once combat has been quiet long enough, and keeps
## the health bar in sync either way.
func _update_combat_regen(delta: float) -> void:
	_time_since_combat += delta
	if _time_since_combat > COMBAT_MEMORY_TIME and health < max_health:
		health = min(max_health, health + health_regen * delta)
	_refresh_health_bar()

## Marks this combatant as having just been involved in a hit (attacking or
## attacked), resetting the regen-delay timer.
func _note_combat_activity() -> void:
	_time_since_combat = 0.0

## Resolves an incoming hit of `amount` from `attacker`: may be evaded based
## on this combatant's dexterity (a floating "Miss" instead of damage),
## otherwise applies the damage, shows kind-specific feedback (see
## _show_damage_feedback), and triggers death at 0 HP.
func take_damage(amount: float, _attacker: Node) -> void:
	_note_combat_activity()
	if randf() < _evasion_chance():
		Effects.spawn_floating_text(get_parent(), global_position + Vector3(0.0, 1.3, 0.0), "Miss", Color(0.85, 0.85, 0.85))
		return
	health -= amount
	_show_damage_feedback(amount)
	if health <= 0.0:
		_on_death()

## Default damage feedback: a "hit landed" read (neutral/rewarding rather
## than alarming) -- this is what Enemy uses as-is, since the player taking
## a chunk out of the enemy's health is a good thing. Blob overrides this
## with a more urgent look, since a blob taking damage is the bad case.
func _show_damage_feedback(amount: float) -> void:
	var text_pos := global_position + Vector3(randf_range(-0.15, 0.15), 1.3, randf_range(-0.15, 0.15))
	Effects.spawn_floating_text(get_parent(), text_pos, "-%d" % int(round(amount)), Color(1.0, 0.85, 0.3))
	Effects.spawn_impact(get_parent(), global_position + Vector3(0.0, 0.6, 0.0), Color(1.0, 0.8, 0.3), 5)

## Chance this combatant evades an incoming hit, scaling with its dexterity
## and capped so a defender is never fully un-hittable.
func _evasion_chance() -> float:
	return clamp(dexterity * EVASION_PER_DEXTERITY, 0.0, MAX_EVASION_CHANCE)

## Default death behavior: a burst of particles, then removal from the
## scene. Subclasses may override to add kind-specific handling (e.g. World
## pruning a dead blob from the current selection) -- call super() to keep
## the shared VFX-and-free behavior.
func _on_death() -> void:
	Effects.spawn_impact(get_parent(), global_position + Vector3(0.0, 0.7, 0.0), Color(0.5, 0.1, 0.1), 16)
	queue_free()
