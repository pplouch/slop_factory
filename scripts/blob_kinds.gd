extends Node
## BlobKinds (Registry pattern, autoload).
##
## A small data-driven catalog of the hireable blob archetypes: their stat
## multipliers (layered on top of GameManager's global upgrades), hire cost,
## and how they look. BuildingMenu reads this to build its Hire section
## without any per-kind UI code; Blob reads it to compute final stats and
## cosmetics from its `kind_id`. Adding a new kind is a one-line addition
## here -- no scene or UI changes required.

## Plain data holder for one blob archetype. Not a Resource/class_name on
## purpose: kinds are baked-in game balance data, not something a designer
## needs to save as a .tres asset.
class Kind:
	var id: String
	var display_name: String
	var hire_cost: int
	var speed_mult: float
	var capacity_mult: float
	var harvest_mult: float
	var body_scale: float
	var hue: float
	var saturation: float
	var value: float
	## Short flavor blurb describing what this kind is best used for --
	## surfaced by UnitInfoPanel next to the standing-order buttons whenever
	## a unit (or group) of this kind is selected.
	var trait_description: String

	func _init(p_id: String, p_name: String, p_cost: int, p_speed: float, p_capacity: float,
			p_harvest: float, p_scale: float, p_hue: float, p_sat: float, p_val: float,
			p_trait_description: String = "") -> void:
		id = p_id
		display_name = p_name
		hire_cost = p_cost
		speed_mult = p_speed
		capacity_mult = p_capacity
		harvest_mult = p_harvest
		body_scale = p_scale
		hue = p_hue
		saturation = p_sat
		value = p_val
		trait_description = p_trait_description

	## Short "Spd 1.6x Cap 0.6x Pwr 0.8x" style summary for hire-menu rows.
	func stat_summary() -> String:
		return "Spd %.1fx  Cap %.1fx  Pwr %.1fx" % [speed_mult, capacity_mult, harvest_mult]

	## This kind's body tint as a Color, for UnitInfoPanel's per-kind group
	## boxes -- the exact same hue/saturation/value Blob itself reads to
	## color its own visuals, so a kind's UI box always matches its units.
	func body_color() -> Color:
		return Color.from_hsv(hue, saturation, value)

var _kinds: Dictionary = {}
var _ordered_ids: Array = []


## Godot lifecycle hook: registers every playable blob archetype. Balanced
## around the "worker" as the 1.0x baseline: scouts trade capacity/power for
## speed, haulers trade speed for capacity, brutes trade speed for harvest
## power.
func _ready() -> void:
	_register(Kind.new("worker", "Worker", 15, 1.0, 1.0, 1.0, 1.0, 0.55, 0.45, 0.95,
		"Balanced all-rounder, good at everything and best at nothing."))
	_register(Kind.new("scout", "Scout", 20, 1.6, 0.6, 0.8, 0.82, 0.13, 0.65, 0.98,
		"Fastest mover -- best for Explore/Patrol and covering ground."))
	_register(Kind.new("hauler", "Hauler", 25, 0.75, 1.8, 0.9, 1.25, 0.62, 0.5, 0.85,
		"Biggest carry capacity -- fewer trips per resource run."))
	_register(Kind.new("brute", "Brute", 30, 0.85, 1.1, 1.6, 1.2, 0.02, 0.65, 0.9,
		"Hardest hitter and harvester -- best for Hold sentry duty."))

## Adds `kind` to the catalog, preserving registration order for UI display.
func _register(kind: Kind) -> void:
	_kinds[kind.id] = kind
	_ordered_ids.append(kind.id)

## Returns the Kind for `id`, falling back to "worker" for an unknown id
## (e.g. old save data referencing a kind that no longer exists).
func get_kind(id: String) -> Kind:
	return _kinds.get(id, _kinds["worker"])

## Every registered kind id, in registration order -- what BuildingMenu
## iterates to build its Hire section.
func get_ordered_ids() -> Array:
	return _ordered_ids
