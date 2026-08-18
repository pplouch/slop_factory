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
##
## Its CollisionShape3D spans the *full* grid cell (see wall.tscn), not just
## the small visual "Post" mesh -- previously it was post-sized, leaving a
## real gap between two adjacent wall cells' actual colliders even though
## the connector-bar meshes visually bridged them into what looked like one
## continuous fence. Blobs never noticed (they route around the whole
## reserved grid cell via the pathing grid, never testing the physical
## collider), but Enemy has no pathing and walks straight at its target --
## this was the actual cause of enemies passing through fences.

## The real visible post -- a Kenney "wall" module (see assets/Models/FBX
## format/wall.fbx, ext_resource "PostModel" below) instead of the plain
## BoxMesh this used to be (see feature request: "there are a lot of
## buildings parts meshes... use them to enhance the game visuals").
## Its own bundled material/colormap.png is a flat-color "trim sheet" (every
## mesh in this kit UV-maps into a solid-color swatch, no actual surface
## detail baked in) rather than a real stone texture, and this particular
## mesh happens to map into a plain white swatch -- so wall.tscn overrides
## its material with our own tuned StandardMaterial3D (see
## surface_material_override/0 on the nested "wall" node there) instead of
## fighting the kit's own palette-texture UVs to land on the right color.
## PostModel itself carries the scale-to-cell-size transform; this reaches
## one level into its own instanced scene for the actual MeshInstance3D
## _apply_construction_visual needs to rise/reposition, which composes fine
## on top of PostModel's own separate scale regardless.
@onready var _post_mesh: MeshInstance3D = $PostModel/wall
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
