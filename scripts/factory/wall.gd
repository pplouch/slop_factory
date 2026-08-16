class_name Wall
extends LinkableBuilding
## A defensive, grid-placed barrier: solid enough to physically block
## blobs/enemies (see World._structure_blocks_movement and the pathing grid,
## which routes movement around it rather than just locally jittering
## against it), and shows a connector bar toward each neighboring cell that
## also holds a Wall, so a run of walls reads as one continuous fence rather
## than separate isolated posts.
##
## A BuildingKinds entry like Town Hall/StorageDepot/WaterTank (tech-tree
## gated, requires blob construction labor before it blocks anything) rather
## than a standalone always-available factory piece -- `kind_id`,
## `upgrade_level`, `durability`/`max_durability`,
## `is_under_construction`/`construction_progress`, `add_construction_progress()`,
## and `try_upgrade()` all come from BuildableStructure via LinkableBuilding
## (see scripts/core/linkable_building.gd and scripts/core/buildable_structure.gd).
## Never rotates -- its local axes are always the world axes, no facing to
## account for, unlike BeltSegment.

@onready var _post_mesh: MeshInstance3D = $Post
@onready var _post_base_position: Vector3 = _post_mesh.position

@onready var _connectors := {
	"pos_x": $ConnectorPosX,
	"neg_x": $ConnectorNegX,
	"pos_z": $ConnectorPosZ,
	"neg_z": $ConnectorNegZ,
}


## Godot lifecycle hook: joins the same groups a building would (clickable
## via World's existing "clicked a building" flow, and covered by
## DebugMenu's hitbox overlay), sets durability from its BuildingKinds
## entry, and shows the freshly-placed "just started" construction visual.
func _ready() -> void:
	add_to_group("buildings")
	add_to_group("structures")
	_setup_durability()
	_apply_construction_visual(0.0)

## Template Method hook (see BuildableStructure._apply_construction_visual):
## a single mesh that both scales and repositions as it rises.
func _construction_meshes() -> Array:
	return [{"mesh": _post_mesh, "base_position": _post_base_position}]

## Template Method hook (see LinkableBuilding.refresh_connections): a fence
## should only visually merge into another fence, not an unrelated belt.
func _links_to(neighbor: Node) -> bool:
	return neighbor is Wall

## Template Method hook (see LinkableBuilding.refresh_connections): a Wall
## never rotates, so its connector keys are already world-space cardinal
## directions -- no local-axis remap needed the way BeltSegment needs.
func _set_connector_visible(key: String, is_visible: bool) -> void:
	_connectors[key].visible = is_visible
