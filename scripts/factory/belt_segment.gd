extends Node3D
## One grid-cell conveyor segment: carries at most one ResourceItem at a
## time from its back edge to its front edge (in `facing` direction), then
## pushes it onward to whatever sits in the next grid cell -- another belt,
## a Processor's input, or (if that cell is empty) straight into
## GameManager's stockpile, since there's nowhere further to send it.
##
## Deliberately no physics body: belts are low structures blobs should walk
## straight over, not obstacles to route around.
##
## `facing` must be set (by World, at placement time) *before* this node
## enters the tree, since its look-at orientation is set at placement using
## the same value.

const CELL_SIZE := 2.0
const BELT_SPEED := 1.2

## The 4 cardinal grid-cell offsets checked by refresh_connections, in the
## same order as the WALLS dictionary keys below.
const NEIGHBOR_OFFSETS := {
	"pos_x": Vector2i(1, 0),
	"neg_x": Vector2i(-1, 0),
	"pos_z": Vector2i(0, 1),
	"neg_z": Vector2i(0, -1),
}

## Grid direction this belt moves items toward: (1,0)/(-1,0)/(0,1)/(0,-1).
@export var facing: Vector2i = Vector2i(1, 0)

## The item currently riding this belt, or null if empty.
var current_item: Node3D = null

@onready var _tile: MeshInstance3D = $Tile
@onready var _walls := {
	"pos_x": $WallPosX,
	"neg_x": $WallNegX,
	"pos_z": $WallPosZ,
	"neg_z": $WallNegZ,
}

## Built fresh per-instance in _ready() (see _build_floor_material) rather
## than shared from a single .tscn-authored resource -- each belt animates
## its own uv1_offset every frame, and sharing one material across every
## belt instance would mean each instance's _process adds to the *same*
## offset, making the scroll speed up as more belts get placed.
var _floor_material: StandardMaterial3D

## Direction the current item is travelling *into* this cell from, i.e. the
## upstream neighbor's own `facing`. This is NOT always the opposite of
## this belt's own `facing` -- on a turn (this belt facing a different
## direction than the one feeding it), the item visually enters from
## whichever edge the upstream neighbor actually sits behind, not from
## this belt's own "back" edge. Defaults to `facing` (a straight
## pass-through) when nothing hands off an explicit direction.
var _entry_direction: Vector2i

var _progress: float = 0.0


## Godot lifecycle hook: makes this belt discoverable as a hand-off target
## for its upstream neighbor (via World.get_structure_at). Deliberately
## does NOT call refresh_connections() here -- _ready() fires synchronously
## during World's add_child(), before World has set this belt's actual
## global_position/rotation, so a grid-cell lookup at this point would
## check the wrong cell entirely. World calls refresh_connections() itself
## once placement is finished (see _refresh_neighbor_visuals).
func _ready() -> void:
	add_to_group("belts")
	_entry_direction = facing
	_floor_material = _build_floor_material()
	_tile.set_surface_override_material(0, _floor_material)

## Builds a small procedural striped texture (alternating light/dark bands)
## and a material that tiles it several times along the belt's length, so
## _process can scroll uv1_offset to sell motion even when nothing's
## currently riding the belt.
func _build_floor_material() -> StandardMaterial3D:
	var stripe_count := 8
	var band_px := 4
	var img := Image.create(4, stripe_count * band_px, false, Image.FORMAT_RGB8)
	for y in img.get_height():
		var light: bool = (y / band_px) % 2 == 0
		var c := Color(0.34, 0.34, 0.38) if light else Color(0.2, 0.2, 0.23)
		for x in img.get_width():
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.85
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_scale = Vector3(1.0, 5.0, 1.0)
	return mat

## Godot per-frame hook: scrolls the floor texture to sell "this belt is
## moving" even when nothing's currently riding it, and advances the held
## item (if any) along the belt or hands it off once it reaches the far edge.
func _process(delta: float) -> void:
	_floor_material.uv1_offset.y = fmod(_floor_material.uv1_offset.y - (BELT_SPEED / CELL_SIZE) * delta, 1.0)

	if current_item == null:
		return
	if _progress < 1.0:
		_progress = min(1.0, _progress + (BELT_SPEED / CELL_SIZE) * delta)
		_update_item_position()
		if _progress >= 1.0:
			_try_advance_item()
	else:
		_try_advance_item()

## Re-checks all 4 neighboring grid cells and shows/hides this belt's side
## rails to match: a rail hides on any side where an adjacent structure
## exists (belt, extractor, processor, or building), so a chain of placed
## pieces reads as one continuous trough instead of separate boxed tiles --
## including through a 90-degree turn, where the "open" sides are simply
## whichever two edges have neighbors rather than always front/back.
## Called by World once this belt's own placement is finalized (to react to
## already-placed neighbors) and again whenever a structure is placed or
## demolished next to it (see World._refresh_neighbor_visuals).
func refresh_connections() -> void:
	var world = get_parent()
	if world == null:
		return
	var my_cell: Vector2i = world.world_to_grid(global_position)
	for key in NEIGHBOR_OFFSETS.keys():
		var world_offset: Vector2i = NEIGHBOR_OFFSETS[key]
		var has_neighbor := world.get_structure_at(my_cell + world_offset) != null
		var local_key := _world_offset_to_local_wall(world_offset)
		_walls[local_key].visible = not has_neighbor

## Maps a world-space cardinal offset to the local wall key (pos_x/neg_x/
## pos_z/neg_z) it corresponds to on *this* belt's own rotated mesh, since
## a belt's local -Z is always its authored "forward" regardless of which
## world direction `facing` actually points (look_at handles that mapping
## at placement time).
func _world_offset_to_local_wall(world_offset: Vector2i) -> String:
	var world_vec := Vector3(world_offset.x, 0.0, world_offset.y)
	var local_vec: Vector3 = global_transform.basis.inverse() * world_vec
	if absf(local_vec.x) > absf(local_vec.z):
		return "pos_x" if local_vec.x > 0.0 else "neg_x"
	return "pos_z" if local_vec.z > 0.0 else "neg_z"

## Positions the held item along the segment from its actual entry edge
## (see _entry_direction) to its front edge, proportional to `_progress`.
## On a turn these two edges aren't mirror images of each other, so entry
## and exit offsets are computed independently rather than from one shared
## `facing`-based offset.
func _update_item_position() -> void:
	var entry_offset := Vector3(_entry_direction.x, 0.0, _entry_direction.y) * (CELL_SIZE * 0.5)
	var exit_offset := Vector3(facing.x, 0.0, facing.y) * (CELL_SIZE * 0.5)
	current_item.global_position = (global_position - entry_offset).lerp(global_position + exit_offset, _progress)

## Accepts `item` onto this belt if it's currently empty. Called by an
## upstream belt/Extractor/Processor pushing an item toward this cell;
## `from_direction` is the upstream neighbor's own facing (the direction
## the item is travelling as it arrives), used to start the item at the
## correct edge instead of assuming a straight pass-through.
func try_receive_input(item: Node3D, from_direction: Vector2i = Vector2i.ZERO) -> bool:
	if current_item != null:
		return false
	current_item = item
	_entry_direction = from_direction if from_direction != Vector2i.ZERO else facing
	_progress = 0.0
	_update_item_position()
	return true

## Called once the held item reaches this belt's far edge: hands it to
## whatever occupies the next grid cell in `facing` direction, or -- if
## that cell is empty -- delivers it straight to the stockpile (the belt
## line has nowhere further to go, so this doubles as "the end of the
## line auto-collects"). If the next cell is occupied but can't accept it
## right now (e.g. another belt already holding an item), the item simply
## waits at the front edge until it can move on.
func _try_advance_item() -> void:
	var world = get_parent()
	var my_cell: Vector2i = world.world_to_grid(global_position)
	var next_structure: Node = world.get_structure_at(my_cell + facing)

	if next_structure == null:
		var item := current_item
		GameManager.add_resource(item.resource_type, item.amount)
		Effects.spawn_impact(world, item.global_position + Vector3(0.0, 0.3, 0.0), Effects.resource_color(item.resource_type), 4)
		item.queue_free()
		current_item = null
		_progress = 0.0
		return

	if next_structure.has_method("try_receive_input") and next_structure.try_receive_input(current_item, facing):
		current_item = null
		_progress = 0.0
