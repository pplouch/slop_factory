class_name Gate
extends LinkableBuilding
## A defensive grid-placed barrier like Wall, but deliberately *not* solid to
## blobs -- lets your own units pass straight through a wall line instead of
## having to route all the way around it, while still physically blocking
## enemies (see feature request: "add a gate, like a wall... but allows
## units to go through while retaining enemies").
##
## Two separate mechanisms make that split possible, matching how Wall
## blocks movement in the first place (see wall.gd's own header on the two
## layers a wall blocks through):
## - `blocks_movement = false` (overriding LinkableBuilding's default true)
##   keeps this cell *clear* in PathingManager's A*-grid, so a blob's own
##   pathing routes straight across it instead of detouring around like it
##   would for a Wall.
## - Its own `CollisionShape3D` sits on the "GateBarrier" physics layer (see
##   project.godot's `[layer_names]`) instead of Wall's "Resources" layer --
##   a *new* layer specifically so it's invisible to Blob's own
##   `collision_mask` (still 14, unchanged) but visible to Enemy's (updated
##   to 30 alongside this feature -- see enemy.tscn), the same
##   "blobs never test the physical collider" trick Wall's own header
##   describes, just deliberately extended to enemies only rather than by
##   accident via the pathing grid alone. Enemy has no pathing awareness at
##   all (see wall.gd's header: "Enemy... walks straight at its target"), so
##   physical collision is its only way of ever being stopped by this at all.
##
## Only links visually to Wall (see _links_to below), not to another Gate --
## matches the feature request's own wording ("linkable to a wall only").
##
## The real visible archway -- a Kenney "wall-doorway" module (see
## assets/Models/FBX format/wall-doorway.fbx, ext_resource "PostModel"
## below), the same base wall module Wall itself now uses but with a real
## opening built in, at the identical 1.8 scale-to-cell-size Wall uses (see
## wall.gd's own header on why its bundled flat-color trim-sheet texture is
## overridden with our own tuned StandardMaterial3D instead of used as-is).

@onready var _post_mesh: MeshInstance3D = $"PostModel/wall-doorway"
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
	# The whole point of a Gate over a Wall -- see this file's own header on
	# why this alone isn't enough on its own (PathingManager.mark_cell reads
	# this, but Enemy has no pathing awareness at all and is stopped by the
	# physical collider instead, on its own dedicated layer).
	blocks_movement = false
	_setup_durability()
	_apply_construction_visual(0.0)

## Template Method hook (see BuildableStructure._apply_construction_visual):
## a single mesh that both scales and repositions as it rises, same as Wall.
func _construction_meshes() -> Array:
	return [{"mesh": _post_mesh, "base_position": _post_base_position}]

## Template Method hook (see LinkableBuilding.refresh_connections): only
## reads as "a gap in the wall" when flanked by actual Wall pieces (see this
## file's own header on why this doesn't also count another Gate).
func _links_to(neighbor: Node) -> bool:
	return neighbor is Wall

## Template Method hook (see LinkableBuilding.refresh_connections): a Gate
## never rotates, so its connector keys are already world-space cardinal
## directions -- no local-axis remap needed the way BeltSegment needs.
func _set_connector_visible(key: String, is_visible: bool) -> void:
	_connectors[key].visible = is_visible
