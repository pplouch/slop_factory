class_name Wall
extends StaticBody3D
## A defensive, grid-placed barrier: solid enough to physically block
## blobs/enemies (see World._kind_blocks_movement and the pathing grid,
## which routes movement around it rather than just locally jittering
## against it), and shows a connector bar toward each neighboring cell that
## also holds a Wall, so a run of walls reads as one continuous fence
## rather than separate isolated posts -- the same "hide the side that
## doesn't need it" technique BeltSegment uses, simplified since a Wall
## never rotates (its local axes are always the world axes, no facing to
## account for).
##
## Exposes the same kind_id/display_name/durability shape BuildingMenu
## reads for its generic "This Building" info section, even though Wall
## isn't a BuildingKinds entry (no ports, no tech-tree gating -- it's a
## simple always-available factory-grid piece like belt/extractor/processor).

const NEIGHBOR_OFFSETS := {
	"pos_x": Vector2i(1, 0),
	"neg_x": Vector2i(-1, 0),
	"pos_z": Vector2i(0, 1),
	"neg_z": Vector2i(0, -1),
}

var kind_id := "wall"
var display_name := "Wall"
var max_durability := 60
var durability := 60

@onready var _connectors := {
	"pos_x": $ConnectorPosX,
	"neg_x": $ConnectorNegX,
	"pos_z": $ConnectorPosZ,
	"neg_z": $ConnectorNegZ,
}


## Godot lifecycle hook: joins the same groups a building would (clickable
## via World's existing "clicked a building" flow, and covered by
## DebugMenu's hitbox overlay).
func _ready() -> void:
	add_to_group("buildings")
	add_to_group("structures")
	durability = max_durability

## Re-checks all 4 neighboring grid cells and shows a connector bar toward
## any of them that's also a Wall. Called by World once this wall's own
## placement is finalized and whenever a structure is placed/demolished
## next to it (see World._refresh_neighbor_visuals) -- same timing
## reasoning as BeltSegment.refresh_connections.
func refresh_connections() -> void:
	var world = get_parent()
	if world == null:
		return
	var my_cell: Vector2i = world.world_to_grid(global_position)
	for key in NEIGHBOR_OFFSETS.keys():
		var neighbor: Node = world.get_structure_at(my_cell + NEIGHBOR_OFFSETS[key])
		_connectors[key].visible = neighbor is Wall
