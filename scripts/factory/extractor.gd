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

## Duck-typed for BuildingMenu's generic "This Building" info section (see
## Wall for the same pattern) -- an extractor isn't a BuildingKinds entry.
var kind_id := "extractor"
var display_name := "Extractor"

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

## Duck-typed by BuildingMenu (has_method("get_info_text")) to show a line of
## live status beyond the generic name/durability/ports fields.
func get_info_text() -> String:
	if not is_instance_valid(linked_node):
		return "Not linked to a resource node"
	return "Linked to: %s (%d left)" % [linked_node.resource_type, linked_node.amount]

## Signal handler for ExtractTimer: if there's a linked node with resources
## left and a belt waiting in the output cell *with room for another item*,
## pulls yield from the node and spawns it onto that belt. Deliberately
## does NOT harvest at all if the output belt is already occupied (see
## _output_is_free) -- since BeltSegment stopped auto-collecting an
## unlinked run into the stockpile (a belt now just holds its item at the
## front edge indefinitely, see feature backlog 2: "resources should be
## stuck, not destroyed"), a belt sitting at a dead end stays occupied
## *permanently* rather than clearing within a frame or two, so skipping
## the harvest is what actually avoids silently destroying everything
## extracted afterward -- the old "rare race, lost this tick" fallback
## became the common case once belts stopped self-clearing.
func _on_extract_timer_timeout() -> void:
	if not is_instance_valid(linked_node) or linked_node.amount <= 0:
		return

	var world = get_parent()
	var my_cell: Vector2i = world.world_to_grid(global_position)
	var output_structure: Node = world.get_structure_at(my_cell + facing)
	if output_structure == null or not output_structure.has_method("try_receive_input"):
		return
	if not _output_is_free(output_structure):
		return

	var taken: int = linked_node.harvest(EXTRACT_AMOUNT)
	if taken <= 0:
		return

	var output_pos := global_position + Vector3(facing.x, 0.0, facing.y) * (CELL_SIZE * 0.5)
	var item := Effects.spawn_resource_item(get_parent(), output_pos, linked_node.resource_type, taken)
	if not output_structure.try_receive_input(item, facing):
		# Genuinely rare now (something else claimed the slot the same
		# frame) rather than the common case _output_is_free already
		# filters out -- still needs a fallback since harvest() already
		# consumed the resource node's stock by this point.
		item.queue_free()

## Whether `structure` (already confirmed to be a valid try_receive_input
## target) actually has room right now -- false while it's still under
## construction (a freshly-placed BeltSegment starts this way and
## unconditionally rejects try_receive_input until a blob finishes building
## it, per BuildableStructure; without this check harvesting would proceed
## straight into that guaranteed rejection every tick, draining the resource
## node into destroyed items the whole time the belt is being built -- see
## feature backlog: "resources on the belt are invisible"), or duck-typed
## against `current_item` (BeltSegment's single-slot field) otherwise, since
## that's the one receiver kind that can stay full indefinitely; anything
## without that field (a multi-slot buffer like StorageDepot, or no field at
## all) is assumed free and left to its own try_receive_input to reject if
## it disagrees.
func _output_is_free(structure: Node) -> bool:
	if "is_under_construction" in structure and structure.is_under_construction:
		return false
	return not ("current_item" in structure and structure.current_item != null)
