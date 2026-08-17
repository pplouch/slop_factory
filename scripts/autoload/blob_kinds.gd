extends Registry
## BlobKinds (Registry pattern, autoload).
##
## A small data-driven catalog of the hireable blob archetypes: their stat
## multipliers (layered on top of GameManager's global upgrades), hire cost,
## and how they look. BuildingMenu reads this to build its Hire section
## without any per-kind UI code; Blob reads it to compute final stats and
## cosmetics from its `kind_id`. Adding a new kind is a one-line addition
## here -- no scene or UI changes required.
##
## The `_kinds`/`_ordered_ids` storage, `_register()`, and `get_ordered_ids()`
## are inherited from Registry (see scripts/core/registry.gd) -- this file
## only defines the `Kind` shape and the actual roster.

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
	## How much faster/slower than baseline this kind contributes toward an
	## under-construction building's labor requirement (see Blob.command_build
	## / Building.add_construction_progress). Every kind can pitch in --
	## "builder" is just the specialist at it -- so this defaults to a
	## modest 1.0 for kinds that don't explicitly set it.
	var build_mult: float
	## Knowledge cost to unlock this kind for hiring (see
	## GameManager.try_unlock_blob_kind) -- the same "spend knowledge once,
	## permanently available" tech-tree shape BuildingKinds' unlock_cost
	## uses, just for hireable kinds instead of buildings. 0 means always
	## available (only "worker" as of this writing).
	var unlock_cost: int
	## Another BlobKinds id that must already be unlocked first, or "" for
	## no prerequisite -- lets kinds form a simple unlock chain (see _ready).
	var requires: String

	func _init(p_id: String, p_name: String, p_cost: int, p_speed: float, p_capacity: float,
			p_harvest: float, p_scale: float, p_hue: float, p_sat: float, p_val: float,
			p_trait_description: String = "", p_build_mult: float = 1.0,
			p_unlock_cost: int = 0, p_requires: String = "") -> void:
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
		build_mult = p_build_mult
		unlock_cost = p_unlock_cost
		requires = p_requires

	## Short "Spd 1.6x Cap 0.6x Pwr 0.8x" style summary for hire-menu rows.
	func stat_summary() -> String:
		return "Spd %.1fx  Cap %.1fx  Pwr %.1fx" % [speed_mult, capacity_mult, harvest_mult]

	## This kind's body tint as a Color, for UnitInfoPanel's per-kind group
	## boxes -- the exact same hue/saturation/value Blob itself reads to
	## color its own visuals, so a kind's UI box always matches its units.
	func body_color() -> Color:
		return Color.from_hsv(hue, saturation, value)


## Godot lifecycle hook: registers every playable blob archetype. Balanced
## around the "worker" as the 1.0x baseline: scouts trade capacity/power for
## speed, haulers trade speed for capacity, brutes trade speed for harvest
## power. Only "worker" is available from the start (see
## GameManager.unlocked_blob_kinds); the rest form a simple knowledge-gated
## unlock chain -- scout, then hauler, then brute, then builder -- so new
## archetypes open up "over time" as the player researches rather than all
## being hireable immediately (see feature backlog).
func _ready() -> void:
	_default_id = "worker"
	_register(Kind.new("worker", "Worker", 15, 1.0, 1.0, 1.0, 1.0, 0.55, 0.45, 0.95,
		"Balanced all-rounder, good at everything and best at nothing."))
	_register(Kind.new("scout", "Scout", 20, 1.6, 0.6, 0.8, 0.82, 0.13, 0.65, 0.98,
		"Fastest mover -- best for Explore/Patrol and covering ground.", 0.6,
		30, ""))
	_register(Kind.new("hauler", "Hauler", 25, 0.75, 1.8, 0.9, 1.25, 0.62, 0.5, 0.85,
		"Biggest carry capacity -- fewer trips per resource run.", 0.5,
		40, "scout"))
	_register(Kind.new("brute", "Brute", 30, 0.85, 1.1, 1.6, 1.2, 0.02, 0.65, 0.9,
		"Hardest hitter and harvester -- best for Hold sentry duty.", 0.8,
		50, "hauler"))
	_register(Kind.new("builder", "Builder", 22, 1.0, 0.8, 0.7, 1.05, 0.11, 0.55, 0.92,
		"Slower harvester, but constructs buildings far faster than anyone else.", 2.5,
		60, "brute"))

## Thin covariant override: keeps callers' `var kind := BlobKinds.get_kind(id)`
## statically typed as `Kind` (with BlobKinds' own fields) rather than the
## untyped return Registry's base version has to use to stay generic.
func get_kind(id: String) -> Kind:
	return super.get_kind(id)
