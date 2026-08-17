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
	## This kind's dominant/most recognizable mesh color, matching its own
	## scene -- purely a UI convenience (BuildPalette/TechTreePanel icon
	## swatches, see Effects.make_swatch_texture), not read anywhere the
	## actual 3D scene is built.
	var display_color: Color

	func _init(p_id: String, p_name: String, p_scene_path: String, p_build_cost: int,
			p_input_ports: Array, p_output_ports: Array, p_unlock_cost: int, p_requires: String,
			p_max_durability: int, p_upgrade_costs: Array, p_upgrade_perks: Array,
			p_build_labor: float = 20.0, p_display_color: Color = Color.WHITE) -> void:
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
		display_color = p_display_color


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
		30.0, Color(0.78, 0.68, 0.5)
	))
	_register(Kind.new(
		"storage_depot", "Storage Depot", "res://scenes/buildings/storage_depot.tscn", 40,
		[Vector2i(0, -1), Vector2i(-1, 0)], [Vector2i(0, 1), Vector2i(1, 0)], 60, "town_hall",
		100, [35, 70],
		["Buffer capacity +2", "Buffer capacity +2 again"],
		18.0, Color(0.45, 0.32, 0.55)
	))
	_register(Kind.new(
		"water_tank", "Water Tank", "res://scenes/buildings/water_tank.tscn", 35,
		[Vector2i(0, -1)], [Vector2i(0, 1)], 50, "town_hall",
		90, [30, 60],
		["Buffer capacity +4", "Buffer capacity +4 again"],
		16.0, Color(0.3, 0.55, 0.68)
	))
	# Wall and Belt are LinkableBuilding entries (see scripts/core/linkable_building.gd)
	# rather than fixed always-available factory pieces -- they still need to
	# stay available from the very start, though (a new player has no Town
	# Hall yet to unlock anything from), so GameManager seeds both "wall" and
	# "belt" as already-unlocked in `unlocked_buildings` alongside "town_hall"
	# rather than relying on `unlock_cost` alone (0 cost still means "must be
	# manually unlocked via BuildingMenu" unless also seeded). Neither has a
	# fixed input/output port shape (Wall has none at all; Belt accepts from
	# any side but its own facing) so both leave input_ports/output_ports empty.
	_register(Kind.new(
		"wall", "Wall", "res://scenes/factory/wall.tscn", 8,
		[], [], 0, "",
		60, [],
		[],
		8.0, Color(0.55, 0.52, 0.48)
	))
	_register(Kind.new(
		"belt", "Belt", "res://scenes/factory/belt_segment.tscn", 5,
		[], [], 0, "",
		40, [],
		[],
		6.0, Color(0.15, 0.15, 0.18)
	))
	# Road is a LinkableBuilding like Wall/Belt (see scripts/factory/road.gd)
	# and, like them, seeded unlocked from the start -- basic infrastructure
	# a new player might want early, with no real reason to gate it behind
	# research the way Pipe (water-specific) is.
	_register(Kind.new(
		"road", "Road", "res://scenes/factory/road.tscn", 6,
		[], [], 0, "",
		50, [],
		[],
		7.0, Color(0.3, 0.3, 0.32)
	))
	# Research Center is the tech tree's knowledge source (see
	# scripts/buildings/research_center.gd) -- its own upgrade tiers boost
	# its production rate, priced in knowledge like every other tier/perk
	# (see BuildableStructure.try_upgrade).
	_register(Kind.new(
		"research_center", "Research Center", "res://scenes/buildings/research_center.tscn", 60,
		[], [], 80, "town_hall",
		110, [40, 80],
		["Knowledge trickle +50%", "Knowledge trickle +50% again"],
		22.0, Color(0.25, 0.65, 0.7)
	))
	# The next 4 are stub buildings (see scripts/buildings/simple_building.gd
	# and CLAUDE.md's feature backlog: "New building stubs, logic not
	# required yet") -- construction/durability/upgrades already work via
	# BuildableStructure, but none of them do anything special yet, so all
	# leave input_ports/output_ports/upgrade_costs/upgrade_perks empty rather
	# than describing effects/connections that don't exist.
	_register(Kind.new(
		"vegetable_patch", "Patch of Vegetables", "res://scenes/buildings/vegetable_patch.tscn", 20,
		[], [], 30, "town_hall",
		40, [],
		[],
		10.0, Color(0.35, 0.62, 0.25)
	))
	_register(Kind.new(
		"school", "School", "res://scenes/buildings/school.tscn", 70,
		[], [], 100, "town_hall",
		120, [],
		[],
		26.0, Color(0.65, 0.7, 0.78)
	))
	_register(Kind.new(
		"tavern", "Tavern", "res://scenes/buildings/tavern.tscn", 55,
		[], [], 70, "town_hall",
		100, [],
		[],
		20.0, Color(0.5, 0.15, 0.12)
	))
	_register(Kind.new(
		"house", "House", "res://scenes/buildings/house.tscn", 30,
		[], [], 40, "town_hall",
		80, [],
		[],
		14.0, Color(0.45, 0.28, 0.18)
	))
	# Pipe is a LinkableBuilding (see scripts/factory/pipe.gd) like Wall/Belt,
	# but -- unlike them -- gated behind water_tank rather than seeded
	# unlocked from the start: a pipe has no reason to exist before there's
	# water infrastructure to connect.
	_register(Kind.new(
		"pipe", "Pipe", "res://scenes/factory/pipe.tscn", 8,
		[], [], 40, "water_tank",
		50, [],
		[],
		8.0, Color(0.5, 0.55, 0.6)
	))

## Thin covariant override: keeps callers' `var kind := BuildingKinds.get_kind(id)`
## statically typed as `Kind` (with BuildingKinds' own fields). Returns null
## if `id` isn't a building kind at all (used by World to tell "is this a
## building placement?" apart from a factory-piece placement) -- Registry's
## default `_default_id = ""` already gives that behavior.
func get_kind(id: String) -> Kind:
	return super.get_kind(id)
