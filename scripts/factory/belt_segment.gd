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

## Grid direction this belt moves items toward: (1,0)/(-1,0)/(0,1)/(0,-1).
@export var facing: Vector2i = Vector2i(1, 0)

## The item currently riding this belt, or null if empty.
var current_item: Node3D = null

var _progress: float = 0.0


## Godot lifecycle hook: makes this belt discoverable as a hand-off target
## for its upstream neighbor (via World.get_structure_at).
func _ready() -> void:
	add_to_group("belts")

## Godot per-frame hook: advances the held item along the belt, or attempts
## to hand it off once it reaches the far edge.
func _process(delta: float) -> void:
	if current_item == null:
		return
	if _progress < 1.0:
		_progress = min(1.0, _progress + (BELT_SPEED / CELL_SIZE) * delta)
		_update_item_position()
		if _progress >= 1.0:
			_try_advance_item()
	else:
		_try_advance_item()

## Positions the held item along the segment from its back edge to its
## front edge, proportional to `_progress`.
func _update_item_position() -> void:
	var offset := Vector3(facing.x, 0.0, facing.y) * (CELL_SIZE * 0.5)
	current_item.global_position = (global_position - offset).lerp(global_position + offset, _progress)

## Accepts `item` onto this belt if it's currently empty. Called by an
## upstream belt/Extractor/Processor pushing an item toward this cell.
func try_receive_input(item: Node3D) -> bool:
	if current_item != null:
		return false
	current_item = item
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

	if next_structure.has_method("try_receive_input") and next_structure.try_receive_input(current_item):
		current_item = null
		_progress = 0.0
