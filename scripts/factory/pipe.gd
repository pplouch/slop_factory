class_name Pipe
extends LinkableBuilding
## A water-infrastructure LinkableBuilding counterpart to Wall/BeltSegment --
## visually merges with adjacent Pipes the same way Wall merges with
## adjacent Walls (see LinkableBuilding.refresh_connections), but carries no
## actual water-transport logic yet -- grouped with the other new-building
## stubs in CLAUDE.md's feature backlog as "logic not required yet".
##
## A BuildingKinds entry (tech-tree gated behind `water_tank`, since pipes
## have no reason to exist before there's water infrastructure to connect)
## rather than a standalone always-available factory piece, same reasoning
## as Wall/Belt's own BuildingKinds migration (see scripts/factory/wall.gd).
##
## `kind_id`, `upgrade_level`, `durability`/`max_durability`,
## `is_under_construction`/`construction_progress`, `add_construction_progress()`,
## and `try_upgrade()` all come from BuildableStructure via LinkableBuilding.

@onready var _post_mesh: MeshInstance3D = $Post
@onready var _post_base_position: Vector3 = _post_mesh.position

@onready var _connectors := {
	"pos_x": $ConnectorPosX,
	"neg_x": $ConnectorNegX,
	"pos_z": $ConnectorPosZ,
	"neg_z": $ConnectorNegZ,
}


## Godot lifecycle hook: same shape as Wall's -- see scripts/factory/wall.gd.
func _ready() -> void:
	add_to_group("buildings")
	add_to_group("structures")
	_setup_durability()
	_apply_construction_visual(0.0)

## Template Method hook (see BuildableStructure._apply_construction_visual):
## a single mesh that both scales and repositions as it rises.
func _construction_meshes() -> Array:
	return [{"mesh": _post_mesh, "base_position": _post_base_position}]

## Template Method hook (see LinkableBuilding.refresh_connections): a pipe
## should only visually merge into another pipe, not an unrelated wall/belt.
func _links_to(neighbor: Node) -> bool:
	return neighbor is Pipe

## Template Method hook (see LinkableBuilding.refresh_connections): a Pipe
## never rotates, so its connector keys are already world-space cardinal
## directions -- no local-axis remap needed the way BeltSegment needs.
func _set_connector_visible(key: String, is_visible: bool) -> void:
	_connectors[key].visible = is_visible
