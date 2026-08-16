extends StaticBody3D
## Automatically harvests a linked resource node over time and feeds the
## yield onto its output belt -- no blob required. Only produces while a
## belt sits in its output cell; with nothing to hand off to, it just sits
## idle rather than losing the harvested resources.
##
## `facing` and `linked_node` are set by World at placement time, `facing`
## before this node enters the tree (its look-at orientation uses the same
## value) and `linked_node` right after (once the node exists so World can
## look up the nearby resource node to bind it to).

const CELL_SIZE := 2.0
const EXTRACT_AMOUNT := 2

## Grid direction this extractor's output belt must be placed in.
@export var facing: Vector2i = Vector2i(1, 0)

## The resource node this extractor draws from. Set by World right after
## placement (found via a nearby-resource-node search); harvesting is a
## no-op while this is null or empty.
var linked_node: Node = null

@onready var extract_timer: Timer = $ExtractTimer


## Godot lifecycle hook: registers for grid lookup by World and starts the
## extraction timer.
func _ready() -> void:
	add_to_group("structures")
	extract_timer.timeout.connect(_on_extract_timer_timeout)

## Signal handler for ExtractTimer: if there's a linked node with resources
## left and a belt waiting in the output cell, pulls yield from the node
## and spawns it onto that belt.
func _on_extract_timer_timeout() -> void:
	if not is_instance_valid(linked_node) or linked_node.amount <= 0:
		return

	var world = get_parent()
	var my_cell: Vector2i = world.world_to_grid(global_position)
	var output_structure: Node = world.get_structure_at(my_cell + facing)
	if output_structure == null or not output_structure.has_method("try_receive_input"):
		return

	var taken: int = linked_node.harvest(EXTRACT_AMOUNT)
	if taken <= 0:
		return

	var output_pos := global_position + Vector3(facing.x, 0.0, facing.y) * (CELL_SIZE * 0.5)
	var item := Effects.spawn_resource_item(get_parent(), output_pos, linked_node.resource_type, taken)
	if not output_structure.try_receive_input(item):
		# Belt was free a moment ago but got claimed by something else this
		# frame; a rare race, not worth more machinery to avoid -- the
		# harvested amount is simply lost this tick.
		item.queue_free()
