extends StaticBody3D
## Converts one resource type into another over time: a single fixed
## recipe for now (wood -> planks). Consumes input items delivered onto its
## input side (a belt feeding it from the cell opposite `facing`) and, once
## a full batch has arrived, produces the output onto its output side (a
## belt in the `facing` cell), or auto-collects to the stockpile if nothing
## is there to hand off to -- the same "end of the line" rule BeltSegment
## uses.
##
## `facing` is set by World at placement time, before this node enters the
## tree (its look-at orientation uses the same value).

const CELL_SIZE := 2.0
const INPUT_TYPE := "wood"
const INPUT_AMOUNT := 2
const OUTPUT_TYPE := "planks"
const OUTPUT_AMOUNT := 1
const PROCESS_TIME := 2.0

## Grid direction this processor's output belt must be placed in; its
## input belt must feed in from the opposite direction.
@export var facing: Vector2i = Vector2i(1, 0)

## Duck-typed for BuildingMenu's generic "This Building" info section (see
## Wall for the same pattern) -- a processor isn't a BuildingKinds entry.
var kind_id := "processor"
var display_name := "Processor"

## How many INPUT_TYPE items have been received but not yet consumed by a
## processing batch.
var buffered_input: int = 0

var _is_processing: bool = false
var _processing_elapsed: float = 0.0


## Godot lifecycle hook: registers for grid lookup by World.
func _ready() -> void:
	add_to_group("structures")

## Duck-typed by BuildingMenu (has_method("get_info_text")) to show a line of
## live status beyond the generic name/durability/ports fields.
func get_info_text() -> String:
	return "Recipe: %d %s -> %d %s\nBuffered: %d/%d%s" % [
		INPUT_AMOUNT, INPUT_TYPE, OUTPUT_AMOUNT, OUTPUT_TYPE,
		buffered_input, INPUT_AMOUNT,
		" (processing...)" if _is_processing else ""
	]

## Godot per-frame hook: advances an in-progress batch, or starts a new one
## once enough input has been buffered *and* the output side has room (see
## _output_is_free) -- doesn't apply to a genuinely empty output cell,
## which still auto-collects to the stockpile in _finish_batch, only to an
## output belt that's already holding an item. Since BeltSegment stopped
## auto-collecting an unlinked run into the stockpile (see feature backlog
## 2: "resources should be stuck, not destroyed"), a belt at a dead end
## now stays occupied indefinitely rather than clearing within a frame or
## two -- without this check, every batch after the first would still
## "finish" and bypass straight to the stockpile instead of ever visibly
## riding the belt, since _finish_batch's own fallback silently succeeds
## whenever the belt rejects delivery.
func _process(delta: float) -> void:
	if _is_processing:
		_processing_elapsed += delta
		if _processing_elapsed >= PROCESS_TIME:
			_finish_batch()
	elif buffered_input >= INPUT_AMOUNT and _output_is_free():
		_is_processing = true
		_processing_elapsed = 0.0

## Whether the structure (if any) in this processor's output cell has room
## right now -- true if the cell is empty (nothing to wait on, _finish_batch
## auto-collects); false while that structure is still under construction (a
## freshly-placed BeltSegment unconditionally rejects try_receive_input until
## a blob finishes building it -- without this check a batch would "finish"
## straight into that guaranteed rejection and fall back to the stockpile,
## never once visibly riding the belt even after it's done) or, once built,
## only when it's specifically a BeltSegment already holding an item, the one
## receiver kind that can stay full indefinitely.
func _output_is_free() -> bool:
	var world = get_parent()
	var my_cell: Vector2i = world.world_to_grid(global_position)
	var output_structure: Node = world.get_structure_at(my_cell + facing)
	if output_structure == null:
		return true
	if "is_under_construction" in output_structure and output_structure.is_under_construction:
		return false
	return not ("current_item" in output_structure and output_structure.current_item != null)

## Accepts `item` into the input buffer if it's the recipe's input type and
## there's room for it (capped at one recipe's worth waiting at a time, so
## upstream belts naturally back up rather than the buffer growing without
## bound). The item itself is consumed immediately -- it becomes internal
## state rather than a visible object once "inside" the machine.
## `_from_direction` is accepted (matching BeltSegment's signature so a
## belt can hand off to either without checking which) but unused --
## consumed items don't need positioning.
func try_receive_input(item: Node3D, _from_direction: Vector2i = Vector2i.ZERO) -> bool:
	if item.resource_type != INPUT_TYPE or buffered_input >= INPUT_AMOUNT:
		return false
	buffered_input += 1
	item.queue_free()
	return true

## Completes a processing batch: consumes the buffered input and either
## hands the output to whatever's in the output cell or, if that cell is
## empty, delivers it straight to the stockpile.
func _finish_batch() -> void:
	_is_processing = false
	_processing_elapsed = 0.0
	buffered_input -= INPUT_AMOUNT

	var world = get_parent()
	var my_cell: Vector2i = world.world_to_grid(global_position)
	var output_structure: Node = world.get_structure_at(my_cell + facing)
	var output_pos := global_position + Vector3(facing.x, 0.0, facing.y) * (CELL_SIZE * 0.5)
	var item := Effects.spawn_resource_item(world, output_pos, OUTPUT_TYPE, OUTPUT_AMOUNT)

	if output_structure and output_structure.has_method("try_receive_input") and output_structure.try_receive_input(item, facing):
		return
	GameManager.add_resource(OUTPUT_TYPE, OUTPUT_AMOUNT)
	item.queue_free()
