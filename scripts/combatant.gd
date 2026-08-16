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

var max_health: float = 10.0
var health: float = 10.0
var health_regen: float = 0.0
var dexterity: float = 1.0

## Seconds since this combatant last landed or received a hit. Regen only
## kicks in once this exceeds COMBAT_MEMORY_TIME, so it doesn't visibly tick
## up mid-fight.
var _time_since_combat: float = COMBAT_MEMORY_TIME + 1.0


## Called every physics frame by a subclass: ages out the combat-memory
## timer and applies regen once combat has been quiet long enough.
func _update_combat_regen(delta: float) -> void:
	_time_since_combat += delta
	if _time_since_combat > COMBAT_MEMORY_TIME and health < max_health:
		health = min(max_health, health + health_regen * delta)

## Marks this combatant as having just been involved in a hit (attacking or
## attacked), resetting the regen-delay timer.
func _note_combat_activity() -> void:
	_time_since_combat = 0.0

## Resolves an incoming hit of `amount` from `attacker`: may be evaded based
## on this combatant's dexterity (a floating "Miss" instead of damage),
## otherwise applies the damage and triggers death at 0 HP.
func take_damage(amount: float, _attacker: Node) -> void:
	_note_combat_activity()
	if randf() < _evasion_chance():
		Effects.spawn_floating_text(get_parent(), global_position + Vector3(0.0, 1.3, 0.0), "Miss", Color(0.85, 0.85, 0.85))
		return
	health -= amount
	var text_pos := global_position + Vector3(randf_range(-0.15, 0.15), 1.3, randf_range(-0.15, 0.15))
	Effects.spawn_floating_text(get_parent(), text_pos, "-%d" % int(round(amount)), Color(1.0, 0.3, 0.25))
	Effects.spawn_impact(get_parent(), global_position + Vector3(0.0, 0.6, 0.0), Color(1.0, 0.2, 0.2), 5)
	if health <= 0.0:
		_on_death()

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
