extends BuildableStructure
## A small pass-through buffer building: accepts items on up to 2 fixed
## input sides (south, west) and re-emits them out through up to 2 fixed
## output sides (north, east) as soon as one is free, holding a short queue
## in between. Demonstrates the multi-port building system (see
## BuildingKinds) with behavior genuinely different from the single-
## input/output Extractor and Processor -- it doesn't consume or transform
## anything, just buffers.
##
## Also keeps a running lifetime tally of every resource type it's ever
## received and how much (see _discovered/get_info_text) -- unlike the
## short-lived `_buffer` (items leave again as soon as an output port is
## free), this only ever grows, giving the player a shipment ledger for
## whatever's been routed through this particular depot.
##
## Unlike belts/Extractor/Processor, this building doesn't rotate to a
## placement-time `facing` -- its ports are fixed world directions matching
## BuildingKinds' registered offsets, and its visual markers are placed to
## match.
##
## `kind_id`, `upgrade_level`, `durability`/`max_durability`,
## `is_under_construction`/`construction_progress`, `add_construction_progress()`,
## and `try_upgrade()` all come from BuildableStructure (see
## scripts/core/buildable_structure.gd).

const CELL_SIZE := 2.0
const BASE_MAX_BUFFER := 4
## Extra buffer slots granted per per-instance upgrade level (see try_upgrade).
const BUFFER_BONUS_PER_LEVEL := 2

## Grid-cell offsets from this building's own cell, matching
## BuildingKinds.get_kind("storage_depot").output_ports. Kept here (rather
## than hardcoded in _process) so the two stay easy to compare at a glance.
const OUTPUT_PORTS := [Vector2i(0, 1), Vector2i(1, 0)]

## Items waiting to be pushed out through whichever output port frees up
## first, oldest first.
var _buffer: Array = []

## resource_type -> lifetime total ever received (see try_receive_input) --
## grows forever, unlike _buffer, so BuildingMenu's info section can show
## "every resource type discovered so far and its amount" for this depot.
## Insertion order (a plain Dictionary already preserves this in GDScript)
## doubles as "discovery order" for get_info_text's listing.
var _discovered: Dictionary = {}

@onready var _body_mesh: MeshInstance3D = $Body
@onready var _body_base_position: Vector3 = _body_mesh.position
@onready var _input_south_mesh: MeshInstance3D = $InputMarkerSouth
@onready var _input_south_base_position: Vector3 = _input_south_mesh.position
@onready var _input_west_mesh: MeshInstance3D = $InputMarkerWest
@onready var _input_west_base_position: Vector3 = _input_west_mesh.position
@onready var _output_north_mesh: MeshInstance3D = $OutputMarkerNorth
@onready var _output_north_base_position: Vector3 = _output_north_mesh.position
@onready var _output_east_mesh: MeshInstance3D = $OutputMarkerEast
@onready var _output_east_base_position: Vector3 = _output_east_mesh.position


## Godot lifecycle hook: registers for both grouping conventions used by
## grid lookup (structures) and by DebugMenu's hitbox overlay (buildings),
## sets durability from its BuildingKinds entry, and shows the freshly-
## placed "just started" construction visual.
func _ready() -> void:
	add_to_group("buildings")
	add_to_group("structures")
	_setup_durability()
	_apply_construction_visual(0.0)

## Template Method hook (see BuildableStructure._apply_construction_visual):
## the body plus all 4 port markers rise together -- a marker left out here
## would render at full size from placement, misleadingly suggesting the
## building already works before construction finishes.
func _construction_meshes() -> Array:
	return [
		{"mesh": _body_mesh, "base_position": _body_base_position},
		{"mesh": _input_south_mesh, "base_position": _input_south_base_position},
		{"mesh": _input_west_mesh, "base_position": _input_west_base_position},
		{"mesh": _output_north_mesh, "base_position": _output_north_base_position},
		{"mesh": _output_east_mesh, "base_position": _output_east_base_position},
	]

## Current buffer capacity: BASE_MAX_BUFFER plus BUFFER_BONUS_PER_LEVEL for
## every per-instance upgrade level bought so far.
func _max_buffer() -> int:
	return BASE_MAX_BUFFER + upgrade_level * BUFFER_BONUS_PER_LEVEL

## Godot per-frame hook: tries to push the oldest buffered item out through
## the first available output port.
func _process(_delta: float) -> void:
	if _buffer.is_empty():
		return
	var world = get_parent()
	var my_cell: Vector2i = world.world_to_grid(global_position)
	for offset in OUTPUT_PORTS:
		var output_structure: Node = world.get_structure_at(my_cell + offset)
		if output_structure == null or not output_structure.has_method("try_receive_input"):
			continue
		var item = _buffer[0]
		item.global_position = global_position + Vector3(offset.x, 0.0, offset.y) * (CELL_SIZE * 0.5)
		if output_structure.try_receive_input(item, offset):
			_buffer.pop_front()
			return

## Accepts `item` into the buffer if there's room, snapping it to this
## building's center to visually show it's "inside" while queued, and
## records it in the lifetime discovery tally (see _discovered) regardless
## of how long it ends up sitting in the buffer. `_from_direction` is
## accepted for interface consistency with BeltSegment/Processor/Building
## but unused -- both input sides feed the same shared buffer.
func try_receive_input(item: Node3D, _from_direction: Vector2i = Vector2i.ZERO) -> bool:
	if is_under_construction or _buffer.size() >= _max_buffer():
		return false
	_discovered[item.resource_type] = _discovered.get(item.resource_type, 0) + item.amount
	item.global_position = global_position + Vector3(0.0, 0.4, 0.0)
	_buffer.append(item)
	return true

## Duck-typed by BuildingMenu (has_method("get_info_text")) to show a line
## of live status beyond the generic name/durability/ports fields.
func get_info_text() -> String:
	var text := "Buffered: %d/%d" % [_buffer.size(), _max_buffer()]
	if _discovered.is_empty():
		return text + "\nDiscovered: nothing yet"
	text += "\nDiscovered:"
	for resource_type in _discovered.keys():
		text += "\n  %s: %d" % [resource_type.capitalize(), _discovered[resource_type]]
	return text
