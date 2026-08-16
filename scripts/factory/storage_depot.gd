extends StaticBody3D
## A small pass-through buffer building: accepts items on up to 2 fixed
## input sides (south, west) and re-emits them out through up to 2 fixed
## output sides (north, east) as soon as one is free, holding a short queue
## in between. Demonstrates the multi-port building system (see
## BuildingKinds) with behavior genuinely different from the single-
## input/output Extractor and Processor -- it doesn't consume or transform
## anything, just buffers.
##
## Unlike belts/Extractor/Processor, this building doesn't rotate to a
## placement-time `facing` -- its ports are fixed world directions matching
## BuildingKinds' registered offsets, and its visual markers are placed to
## match.

const CELL_SIZE := 2.0
const BASE_MAX_BUFFER := 4
## Extra buffer slots granted per per-instance upgrade level (see try_upgrade).
const BUFFER_BONUS_PER_LEVEL := 2

## Grid-cell offsets from this building's own cell, matching
## BuildingKinds.get_kind("storage_depot").output_ports. Kept here (rather
## than hardcoded in _process) so the two stay easy to compare at a glance.
const OUTPUT_PORTS := [Vector2i(0, 1), Vector2i(1, 0)]

## Which BuildingKinds entry this instance is -- set by World at placement
## time, before this node enters the tree. Used by BuildingMenu's generic
## "This Building" info section (durability, upgrade cost/perks).
@export var kind_id: String = "storage_depot"

var upgrade_level := 0
var durability: int
var max_durability: int

## Whether this instance is still being built (see add_construction_progress)
## -- true for every freshly-placed building, since a Storage Depot is only
## ever created via Build Mode. Blocked from upgrading/accepting deliveries
## until done (see Building for the identical Town Hall pattern).
var is_under_construction := true
var construction_progress := 0.0

## Items waiting to be pushed out through whichever output port frees up
## first, oldest first.
var _buffer: Array = []

@onready var _body_mesh: MeshInstance3D = $Body
@onready var _body_base_position: Vector3 = _body_mesh.position


## Godot lifecycle hook: registers for both grouping conventions used by
## grid lookup (structures) and by DebugMenu's hitbox overlay (buildings),
## sets durability from its BuildingKinds entry, and shows the freshly-
## placed "just started" construction visual.
func _ready() -> void:
	add_to_group("buildings")
	add_to_group("structures")
	var kind := BuildingKinds.get_kind(kind_id)
	max_durability = kind.max_durability
	durability = max_durability
	_apply_construction_visual(0.0)

## Called by whichever blob(s) are in ConstructState with this building as
## their pending_build_target, once per physics frame. Finishes
## construction once BuildingKinds' build_labor is reached.
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

## Scales the purely-cosmetic Body mesh -- never the root StaticBody3D's
## collider itself, which stays full-size throughout so the depot already
## occupies/blocks its cell the moment it's placed -- so an in-progress
## instance visibly rises from a low foundation up to its full height.
## position.y is repositioned alongside scale so its base stays anchored to
## the ground instead of shrinking toward its own midpoint.
func _apply_construction_visual(fraction: float) -> void:
	var height_fraction: float = lerp(0.15, 1.0, clamp(fraction, 0.0, 1.0))
	_body_mesh.scale.y = height_fraction
	_body_mesh.position.y = _body_base_position.y * height_fraction

## Current buffer capacity: BASE_MAX_BUFFER plus BUFFER_BONUS_PER_LEVEL for
## every per-instance upgrade level bought so far.
func _max_buffer() -> int:
	return BASE_MAX_BUFFER + upgrade_level * BUFFER_BONUS_PER_LEVEL

## Attempts to spend this instance's next upgrade level's wood cost (see
## BuildingKinds.upgrade_costs). Returns whether it went through.
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
## building's center to visually show it's "inside" while queued.
## `_from_direction` is accepted for interface consistency with
## BeltSegment/Processor/Building but unused -- both input sides feed the
## same shared buffer.
func try_receive_input(item: Node3D, _from_direction: Vector2i = Vector2i.ZERO) -> bool:
	if is_under_construction or _buffer.size() >= _max_buffer():
		return false
	item.global_position = global_position + Vector3(0.0, 0.4, 0.0)
	_buffer.append(item)
	return true
