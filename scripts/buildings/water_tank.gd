extends StaticBody3D
## A dedicated water-storage building: a single-input/single-output buffer
## like StorageDepot, but only accepts the "water" resource type -- a belt
## line feeding it anything else is simply refused, the same way Processor
## refuses an input type that doesn't match its recipe.
##
## Mirrors Building/StorageDepot's construction-gating pattern (see
## add_construction_progress) -- it's a BuildingKinds entry like them, not
## an always-available factory piece like Wall/belt/extractor/processor.

const CELL_SIZE := 2.0
const BASE_MAX_BUFFER := 8
const BUFFER_BONUS_PER_LEVEL := 4
const ACCEPTED_RESOURCE_TYPE := "water"

## Grid-cell offset from this building's own cell, matching
## BuildingKinds.get_kind("water_tank").output_ports.
const OUTPUT_PORT := Vector2i(0, 1)

@export var kind_id: String = "water_tank"

var upgrade_level := 0
var durability: int
var max_durability: int

var is_under_construction := true
var construction_progress := 0.0

var _buffer: Array = []

@onready var _tank_mesh: MeshInstance3D = $Tank
@onready var _tank_base_position: Vector3 = _tank_mesh.position


func _ready() -> void:
	add_to_group("buildings")
	add_to_group("structures")
	var kind := BuildingKinds.get_kind(kind_id)
	max_durability = kind.max_durability
	durability = max_durability
	_apply_construction_visual(0.0)

## Duck-typed by BuildingMenu (has_method("get_info_text")) to show a line
## of live status beyond the generic name/durability/ports fields.
func get_info_text() -> String:
	return "Stores: water only\nBuffer: %d/%d" % [_buffer.size(), _max_buffer()]

func add_construction_progress(amount: float) -> void:
	if not is_under_construction:
		return
	construction_progress += amount
	var required: float = BuildingKinds.get_kind(kind_id).build_labor
	if construction_progress >= required:
		is_under_construction = false
		_apply_construction_visual(1.0)
		Effects.spawn_command_marker(get_parent(), global_position + Vector3(0.0, 0.05, 0.0), Color(1.0, 0.85, 0.3, 1.0))
	else:
		_apply_construction_visual(construction_progress / required)

func _apply_construction_visual(fraction: float) -> void:
	var height_fraction: float = lerp(0.15, 1.0, clamp(fraction, 0.0, 1.0))
	_tank_mesh.scale.y = height_fraction
	_tank_mesh.position.y = _tank_base_position.y * height_fraction

func _max_buffer() -> int:
	return BASE_MAX_BUFFER + upgrade_level * BUFFER_BONUS_PER_LEVEL

func try_upgrade() -> bool:
	if is_under_construction:
		return false
	var kind := BuildingKinds.get_kind(kind_id)
	if upgrade_level >= kind.upgrade_costs.size():
		return false
	if not GameManager.try_spend_wood(kind.upgrade_costs[upgrade_level]):
		return false
	upgrade_level += 1
	return true

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
