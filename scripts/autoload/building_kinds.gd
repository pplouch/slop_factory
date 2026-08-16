extends Registry
## BuildingKinds (Registry pattern, autoload).
##
## Data-driven catalog of placeable building types: their wood build cost,
## input/output port directions (0-2 each, registered as additional
## occupied grid cells so belts can find them via World.get_structure_at),
## and tech-tree unlock requirements (a wood cost plus an optional
## prerequisite building id; 0 cost means unlocked from the start).
## BuildPalette's building buttons and BuildingMenu's "Unlock Buildings"
## section are both generated from get_ordered_ids(), so adding a new
## building type needs no UI changes -- only a _register call here.
##
## The `_kinds`/`_ordered_ids` storage, `_register()`, and `get_ordered_ids()`
## are inherited from Registry (see scripts/core/registry.gd). Registry's
## default `_default_id = ""` already matches this catalog's fallback policy
## (return null for an unknown id, rather than a fallback entry), so it's
## left untouched here.

## Plain data holder for one building type. Ports are Vector2i grid-cell
## *offsets* from the building's own anchor cell (not directions on a
## rotating facing -- buildings don't rotate, unlike belts/extractors).
class Kind:
	var id: String
	var display_name: String
	var scene: PackedScene
	var build_cost: int
	var input_ports: Array
	var output_ports: Array
	var unlock_cost: int
	var requires: String
	## Structural integrity shown in the building info modal -- informational
	## for now (no combat mechanic damages a building yet), max_durability sets
	## the ceiling a building instance's own `durability` field starts at.
	var max_durability: int
	## Wood cost of each per-instance upgrade level, e.g. [30, 60, 100] for a
	## 3-level building. A building instance's own `upgrade_level` indexes
	## into this (and upgrade_perks) via BuildingMenu's "This Building" section.
	var upgrade_costs: Array
	## Player-facing description of what each corresponding upgrade_costs
	## level actually does -- the building script itself reads its own
	## upgrade_level to apply the numeric effect described here.
	var upgrade_perks: Array
	## Total seconds of blob labor (see Blob.build_rate) a freshly-placed
	## instance needs before it finishes construction and becomes usable --
	## see Building/StorageDepot's add_construction_progress.
	var build_labor: float

	func _init(p_id: String, p_name: String, p_scene_path: String, p_build_cost: int,
			p_input_ports: Array, p_output_ports: Array, p_unlock_cost: int, p_requires: String,
			p_max_durability: int, p_upgrade_costs: Array, p_upgrade_perks: Array,
			p_build_labor: float = 20.0) -> void:
		id = p_id
		display_name = p_name
		scene = load(p_scene_path)
		build_cost = p_build_cost
		input_ports = p_input_ports
		output_ports = p_output_ports
		unlock_cost = p_unlock_cost
		requires = p_requires
		max_durability = p_max_durability
		upgrade_costs = p_upgrade_costs
		upgrade_perks = p_upgrade_perks
		build_labor = p_build_labor


## Godot lifecycle hook: registers every building type. Town Hall is the
## tech-tree root (unlock_cost 0 = always available, no prerequisite) since
## the player must be able to build *something* to receive resources at
## all; Storage Depot demonstrates the full 2-input/2-output port range and
## requires Town Hall to unlock.
func _ready() -> void:
	_register(Kind.new(
		"town_hall", "Town Hall", "res://scenes/buildings/building.tscn", 50,
		[Vector2i(0, -1), Vector2i(-1, 0)], [], 0, "",
		150, [40, 80, 140],
		["Spawn timer 15% faster", "Spawn timer 15% faster again, hire costs -10%", "Free spawns arrive as a random kind instead of always worker"],
		30.0
	))
	_register(Kind.new(
		"storage_depot", "Storage Depot", "res://scenes/buildings/storage_depot.tscn", 40,
		[Vector2i(0, -1), Vector2i(-1, 0)], [Vector2i(0, 1), Vector2i(1, 0)], 60, "town_hall",
		100, [35, 70],
		["Buffer capacity +2", "Buffer capacity +2 again"],
		18.0
	))
	_register(Kind.new(
		"water_tank", "Water Tank", "res://scenes/buildings/water_tank.tscn", 35,
		[Vector2i(0, -1)], [Vector2i(0, 1)], 50, "town_hall",
		90, [30, 60],
		["Buffer capacity +4", "Buffer capacity +4 again"],
		16.0
	))

## Thin covariant override: keeps callers' `var kind := BuildingKinds.get_kind(id)`
## statically typed as `Kind` (with BuildingKinds' own fields). Returns null
## if `id` isn't a building kind at all (used by World to tell "is this a
## building placement?" apart from a factory-piece placement) -- Registry's
## default `_default_id = ""` already gives that behavior.
func get_kind(id: String) -> Kind:
	return super.get_kind(id)
