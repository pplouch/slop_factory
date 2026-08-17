extends BuildableStructure
## Smelts any one ore type (see ORE_TO_BAR) into its matching bar, one batch
## at a time -- a generalized Processor: instead of one fixed recipe, it
## auto-detects which ore the first delivered item is and locks its single
## buffer to that type until the batch clears, then accepts a different ore
## next. Avoids needing a recipe-selection UI (nothing asked for one) while
## still covering Iron/Gold/Silver/Platinum/Slopium with one building
## rather than five near-identical single-recipe ones.
##
## `kind_id`, `upgrade_level`, `durability`/`max_durability`,
## `is_under_construction`/`construction_progress`, `add_construction_progress()`,
## and `try_upgrade()` all come from BuildableStructure (see
## scripts/core/buildable_structure.gd).

const CELL_SIZE := 2.0
const ORE_PER_BATCH := 3
const PROCESS_TIME := 3.0
## Each of this instance's first 2 upgrade levels (see
## BuildingKinds.get_kind("foundry").upgrade_perks) shaves another 20% off
## the smelt time -- read directly from upgrade_level in
## _effective_process_time rather than needing a try_upgrade() override,
## since there's no extra state to react to, just a number to recompute.
const PROCESS_TIME_REDUCTION_PER_LEVEL := 0.2

## Ore resource_type -> the bar resource_type it smelts into (see
## Effects.resource_color, which already maps both sides of each pair to
## the same display color).
const ORE_TO_BAR := {
	"iron": "iron_bar",
	"gold": "gold_bar",
	"silver": "silver_bar",
	"platinum": "platinum_bar",
	"slopium": "slopium_bar",
}

## Grid direction this foundry's output belt must be placed in (input feeds
## from the opposite side) -- an @export like Extractor/Processor's own
## `facing` rather than BuildableStructure's usual fixed world-relative
## BuildingKinds ports, so BuildingManager's existing "facing" in node
## duck-type (see try_place_structure) picks it up for free and 'R' rotates
## it in build mode same as those two (see feature backlog: "when in build
## mode, I can't turn buildings like foundry -- the input and output stays
## at the same place"). Set by World at placement time, before this node
## enters the tree, same as Extractor/Processor.
@export var facing: Vector2i = Vector2i(0, 1)

## Which ore type the single buffer is currently locked to -- "" means
## empty/unlocked, free to start buffering any ore next delivery.
var _buffered_type: String = ""
var _buffered_count: int = 0
var _is_processing: bool = false
var _processing_elapsed: float = 0.0

@onready var _body_mesh: MeshInstance3D = $Body
@onready var _body_base_position: Vector3 = _body_mesh.position
@onready var _furnace_mouth_mesh: MeshInstance3D = $FurnaceMouth
@onready var _furnace_mouth_base_position: Vector3 = _furnace_mouth_mesh.position
@onready var _input_marker_mesh: MeshInstance3D = $InputMarker
@onready var _input_marker_base_position: Vector3 = _input_marker_mesh.position
@onready var _output_marker_mesh: MeshInstance3D = $OutputMarker
@onready var _output_marker_base_position: Vector3 = _output_marker_mesh.position


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
## the body plus both port markers rise together -- a marker left out here
## would render at full size from placement, misleadingly suggesting the
## building already works before construction finishes.
func _construction_meshes() -> Array:
	return [
		{"mesh": _body_mesh, "base_position": _body_base_position},
		{"mesh": _furnace_mouth_mesh, "base_position": _furnace_mouth_base_position},
		{"mesh": _input_marker_mesh, "base_position": _input_marker_base_position},
		{"mesh": _output_marker_mesh, "base_position": _output_marker_base_position},
	]

## Duck-typed by BuildingMenu (has_method("get_info_text")) to show a line
## of live status beyond the generic name/durability/ports fields.
func get_info_text() -> String:
	if _buffered_type == "":
		return "Smelts: any ore (idle)"
	var text := "Smelting: %s (%d/%d)" % [_buffered_type, _buffered_count, ORE_PER_BATCH]
	if _is_processing:
		text += "\nProcessing..."
	return text

## Accepts `item` into the single buffer if it's a known ore, the buffer
## isn't already locked to a *different* ore type, and there's room for a
## full batch. `_from_direction` is accepted for interface consistency with
## BeltSegment/Processor/Building but unused -- the single input side feeds
## the same buffer.
func try_receive_input(item: Node3D, _from_direction: Vector2i = Vector2i.ZERO) -> bool:
	if is_under_construction or not ORE_TO_BAR.has(item.resource_type):
		return false
	if _buffered_type != "" and _buffered_type != item.resource_type:
		return false
	if _buffered_count >= ORE_PER_BATCH:
		return false
	_buffered_type = item.resource_type
	_buffered_count += 1
	item.queue_free()
	return true

## Godot per-frame hook: advances an in-progress batch, or starts a new one
## once a full batch of the locked ore type has been buffered *and* the
## output side has room (see _output_is_free) -- doesn't apply to a
## genuinely empty output cell, which still auto-collects to the stockpile
## in _finish_batch, only to an output belt already holding a bar. Without
## this, a Foundry feeding a dead-end belt would still "finish" every batch
## and bypass straight to the stockpile instead of ever visibly producing a
## bar onto the belt, since BeltSegment no longer auto-collects an unlinked
## run (see feature backlog 2: "resources should be stuck, not destroyed") --
## _finish_batch's own fallback would otherwise silently paper over that.
func _process(delta: float) -> void:
	if _is_processing:
		_processing_elapsed += delta
		if _processing_elapsed >= _effective_process_time():
			_finish_batch()
	elif _buffered_count >= ORE_PER_BATCH and _output_is_free():
		_is_processing = true
		_processing_elapsed = 0.0

## This instance's current smelt time, shortened by its own upgrade_level
## (see PROCESS_TIME_REDUCTION_PER_LEVEL).
func _effective_process_time() -> float:
	return PROCESS_TIME * (1.0 - min(upgrade_level, 2) * PROCESS_TIME_REDUCTION_PER_LEVEL)

## Whether the structure (if any) in this foundry's output cell has room
## right now -- true if the cell is empty (nothing to wait on); false while
## that structure is still under construction (a freshly-placed BeltSegment
## unconditionally rejects try_receive_input until a blob finishes building
## it -- without this check a batch would "finish" straight into that
## guaranteed rejection and fall back to the stockpile, never once visibly
## riding the belt even after it's done) or, once built, only when it's
## specifically a BeltSegment already holding an item, the one receiver kind
## that can stay full indefinitely.
func _output_is_free() -> bool:
	var world = get_parent()
	var my_cell: Vector2i = world.world_to_grid(global_position)
	var output_structure: Node = world.get_structure_at(my_cell + facing)
	if output_structure == null:
		return true
	if "is_under_construction" in output_structure and output_structure.is_under_construction:
		return false
	return not ("current_item" in output_structure and output_structure.current_item != null)

## Completes a smelting batch: consumes ORE_PER_BATCH of the buffered ore
## and either hands the resulting bar to whatever's in the output cell or,
## if that cell is empty, delivers it straight to the stockpile -- same
## "end of the line" fallback Processor uses. Unlocks the buffer (resets
## _buffered_type to "") once it's fully drained, so a different ore can
## start accumulating next.
func _finish_batch() -> void:
	_is_processing = false
	_processing_elapsed = 0.0
	_buffered_count -= ORE_PER_BATCH
	var bar_type: String = ORE_TO_BAR[_buffered_type]
	if _buffered_count <= 0:
		_buffered_count = 0
		_buffered_type = ""

	var world = get_parent()
	var my_cell: Vector2i = world.world_to_grid(global_position)
	var output_structure: Node = world.get_structure_at(my_cell + facing)
	var output_pos := global_position + Vector3(facing.x, 0.0, facing.y) * (CELL_SIZE * 0.5)
	var item := Effects.spawn_resource_item(world, output_pos, bar_type, 1)

	if output_structure and output_structure.has_method("try_receive_input") and output_structure.try_receive_input(item, facing):
		return
	GameManager.add_resource(bar_type, 1)
	item.queue_free()
