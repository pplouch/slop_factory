class_name Road
extends LinkableBuilding
## A flat, walkable LinkableBuilding that speeds up any Blob crossing it
## (see Blob._current_terrain_speed_multiplier, which duck-types
## get_speed_multiplier on whatever occupies a blob's current cell) --
## visually merges with adjacent Roads the same way Wall merges with
## adjacent Walls, hiding a raised curb edge wherever a neighboring Road
## continues so a paved run reads as one continuous lane rather than
## separate tiles.
##
## `blocks_movement` is overridden false, the same override BeltSegment
## uses and for the same reason: the entire point of a Road is to be
## walked *on*, not routed around -- leaving LinkableBuilding's `true`
## default would make the pathing grid treat every Road cell as a solid
## obstacle, defeating the speed boost before a blob could ever reach it.
##
## A BuildingKinds entry like Wall/Belt/Pipe (tech-tree gated, requires
## blob construction labor before it speeds anyone up), seeded unlocked
## from the start alongside Wall/Belt since a new player has no Town Hall
## yet to unlock anything else from and there's no real reason to gate
## basic infrastructure behind research.
##
## `kind_id`, `upgrade_level`, `durability`/`max_durability`,
## `is_under_construction`/`construction_progress`, `add_construction_progress()`,
## and `try_upgrade()` all come from BuildableStructure via LinkableBuilding.

## Multiplier applied to a Blob's movement speed while standing on a
## finished Road (see get_speed_multiplier).
const SPEED_MULTIPLIER := 1.5

@onready var _tile_mesh: MeshInstance3D = $Tile
@onready var _tile_base_position: Vector3 = _tile_mesh.position

@onready var _curbs := {
	"pos_x": $CurbPosX,
	"neg_x": $CurbNegX,
	"pos_z": $CurbPosZ,
	"neg_z": $CurbNegZ,
}


## Godot lifecycle hook: same shape as Wall's -- see scripts/factory/wall.gd.
func _ready() -> void:
	add_to_group("buildings")
	add_to_group("structures")
	blocks_movement = false
	_setup_durability()
	_apply_construction_visual(0.0)

## Duck-typed by Blob._current_terrain_speed_multiplier -- a finished Road
## speeds a blob up; one still under construction has no effect yet, same
## "non-functional until built" convention every other building follows.
func get_speed_multiplier() -> float:
	return 1.0 if is_under_construction else SPEED_MULTIPLIER

## Template Method hook (see BuildableStructure._apply_construction_visual):
## a single mesh that both scales and repositions as it rises.
func _construction_meshes() -> Array:
	return [{"mesh": _tile_mesh, "base_position": _tile_base_position}]

## Template Method hook (see LinkableBuilding.refresh_connections): a road
## should only visually merge into another road, not an unrelated wall/belt.
func _links_to(neighbor: Node) -> bool:
	return neighbor is Road

## Template Method hook (see LinkableBuilding.refresh_connections): a Road
## never rotates, so its curb keys are already world-space cardinal
## directions -- no local-axis remap needed the way BeltSegment needs.
func _set_connector_visible(key: String, is_visible: bool) -> void:
	_curbs[key].visible = not is_visible
