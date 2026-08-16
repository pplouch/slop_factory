extends BuildableStructure
## A dedicated water-storage building: a single-input/single-output buffer
## like StorageDepot, but only accepts the "water" resource type -- a belt
## line feeding it anything else is simply refused, the same way Processor
## refuses an input type that doesn't match its recipe.
##
## `kind_id`, `upgrade_level`, `durability`/`max_durability`,
## `is_under_construction`/`construction_progress`, `add_construction_progress()`,
## and `try_upgrade()` all come from BuildableStructure (see
## scripts/core/buildable_structure.gd).

const CELL_SIZE := 2.0
const BASE_MAX_BUFFER := 8
const BUFFER_BONUS_PER_LEVEL := 4
const ACCEPTED_RESOURCE_TYPE := "water"

## Grid-cell offset from this building's own cell, matching
## BuildingKinds.get_kind("water_tank").output_ports.
const OUTPUT_PORT := Vector2i(0, 1)

var _buffer: Array = []

@onready var _tank_mesh: MeshInstance3D = $Tank
@onready var _tank_base_position: Vector3 = _tank_mesh.position


func _ready() -> void:
	add_to_group("buildings")
	add_to_group("structures")
	_setup_durability()
	_apply_construction_visual(0.0)

## Duck-typed by BuildingMenu (has_method("get_info_text")) to show a line
## of live status beyond the generic name/durability/ports fields.
func get_info_text() -> String:
	return "Stores: water only\nBuffer: %d/%d" % [_buffer.size(), _max_buffer()]

## Template Method hook (see BuildableStructure._apply_construction_visual):
## a single mesh that both scales and repositions as it rises.
func _construction_meshes() -> Array:
	return [{"mesh": _tank_mesh, "base_position": _tank_base_position}]

func _max_buffer() -> int:
	return BASE_MAX_BUFFER + upgrade_level * BUFFER_BONUS_PER_LEVEL

## Godot per-frame hook: tries to push the oldest buffered item out through
## its single output port.
func _process(_delta: float) -> void:
	if _buffer.is_empty():
		return
	var world = get_parent()
	var my_cell: Vector2i = world.world_to_grid(global_position)
	var output_structure: Node = world.get_structure_at(my_cell + OUTPUT_PORT)
	if output_structure == null or not output_structure.has_method("try_receive_input"):
		return
	var item = _buffer[0]
	item.global_position = global_position + Vector3(OUTPUT_PORT.x, 0.0, OUTPUT_PORT.y) * (CELL_SIZE * 0.5)
	if output_structure.try_receive_input(item, OUTPUT_PORT):
		_buffer.pop_front()

## Accepts `item` into the buffer only if it's water, there's room, and
## construction is finished. `_from_direction` is accepted for interface
## consistency with BeltSegment/Processor/Building but unused -- the single
## input side feeds the same buffer.
func try_receive_input(item: Node3D, _from_direction: Vector2i = Vector2i.ZERO) -> bool:
	if is_under_construction or item.resource_type != ACCEPTED_RESOURCE_TYPE or _buffer.size() >= _max_buffer():
		return false
	item.global_position = global_position + Vector3(0.0, 0.4, 0.0)
	_buffer.append(item)
	return true
