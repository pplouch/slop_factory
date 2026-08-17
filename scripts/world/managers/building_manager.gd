class_name BuildingManager
extends RefCounted
## Factory placement grid + Build Mode (ghost preview, placement/demolition)
## -- split out of world.gd (see CLAUDE.md's "world.gd -- the central
## controller" section). Kept as one manager rather than split further: a
## placement/demolition both touch the grid, the pathing manager, GameManager
## (spend/refund), and neighbor-visual refresh all in one transaction, so
## separating "the grid" from "build mode" would just add manager-to-manager
## chatter without a real seam.
##
## `world_to_grid`/`grid_to_world` are `static` (pure functions of
## GRID_CELL_SIZE, no instance state) so PathingManager can share the exact
## same conversions without a runtime dependency between the two managers --
## GRID_CELL_SIZE must stay identical between the pathing grid and this one,
## so it lives here as the single source of truth and PathingManager
## references `BuildingManager.GRID_CELL_SIZE`/these functions directly.

const MASK_GROUND := 1

const GRID_CELL_SIZE := 2.0
const EXTRACTOR_LINK_RADIUS := 3.0
const EXTRACTOR_SCENE: PackedScene = preload("res://scenes/factory/extractor.tscn")
const PROCESSOR_SCENE: PackedScene = preload("res://scenes/factory/processor.tscn")
const WATER_EXTRACTOR_SCENE: PackedScene = preload("res://scenes/factory/water_extractor.tscn")
# Belt/Wall/Pipe costs live on their BuildingKinds entries (see
# scripts/autoload/building_kinds.gd) since all three are LinkableBuilding
# entries -- only Extractor/Processor/WaterExtractor (which never joined the
# tech tree) still price through this dict.
const BUILD_COSTS := {"extractor": 25, "processor": 30, "water_extractor": 25}
const GHOST_VALID_COLOR := Color(0.3, 1.0, 0.4, 0.55)
const GHOST_INVALID_COLOR := Color(1.0, 0.3, 0.3, 0.55)
# How far out from the build-mode cursor to scan for legal Water Extractor
# spots -- see _refresh_water_extractor_indicators. Water has no discrete
# per-instance node the way a resource node does, so unlike
# _show_extractor_range_indicators (one disc per resource node, shown for
# the whole loaded world at once) this has to actively sample terrain in a
# bounded area instead, which only stays cheap if that area is local to
# where the player is currently looking to place one.
const WATER_EXTRACTOR_PREVIEW_RADIUS_CELLS := 5
# Port-direction arrows shown next to the build-mode ghost (see
# _refresh_port_indicators) -- colors deliberately reuse the same
# input/output look already established per-instance (WaterTank's blue
# InputMarker, Extractor's orange OutputMarker/OutputArrow) so the build-
# mode preview and the finished building read as the same visual language.
const PORT_ARROW_INPUT_COLOR := Color(0.3, 0.6, 1.0, 0.75)
const PORT_ARROW_OUTPUT_COLOR := Color(1.0, 0.65, 0.2, 0.75)
const PORT_ARROW_SIZE := Vector3(0.22, 0.12, 0.9)

## Grid cell (Vector2i) -> the belt/extractor/processor/building placed
## there. Lets each structure look up its neighbors (e.g. "is there a belt
## in front of me to hand this item to?") without needing direct references
## to each other.
var _grid_structures: Dictionary = {}

var _world: Node3D
var _pathing: PathingManager
var _fog: FogManager

var _build_mode_active := false
var _build_selected_kind := "belt"
var _build_facing := Vector2i(1, 0)
var _build_ghost: Node3D = null
var _build_ghost_material: StandardMaterial3D = null
var _build_ghost_cell := Vector2i.ZERO

# Kinds where holding the mouse button and dragging places a whole line at
# once instead of one click per cell -- LinkableBuilding entries only (see
# scripts/core/linkable_building.gd): a repeated line piece like a fence or
# conveyor run is exactly what a drag gesture is for, unlike a one-off
# building like Town Hall. A short explicit list rather than a derived
# "is LinkableBuilding" check, since checking the type would mean
# instantiating the scene just to ask.
const DRAG_PLACE_KINDS := ["wall", "belt", "pipe"]

var _dragging_place := false
## The most recently *drag*-placed cell (not necessarily the ghost's current
## cell) -- compared against the ghost's cell each mouse-motion event to
## detect "moved to a new cell" and, for Belt, to derive which direction the
## new segment should face (see _try_drag_place).
var _drag_last_cell := Vector2i.ZERO

# Translucent discs shown over every resource node while "extractor" is the
# selected build kind, so the player can see valid linking range at a glance
# instead of guessing and getting an invalid-placement red ghost.
var _extractor_range_indicators: Array = []

# Translucent arrows shown at the ghost's port cells (see
# _refresh_port_indicators) -- world-space nodes, deliberately NOT children
# of _build_ghost: BuildingKinds ports are fixed world-relative offsets
# (buildings never rotate), but _build_ghost itself still gets rotated by
# _build_facing for kinds that DO rotate (belt/extractor/processor), and a
# port arrow parented to it would incorrectly inherit that rotation.
var _port_indicators: Array = []

# Translucent tiles shown over legal (water) spots near the build-mode
# cursor while "water_extractor" is the selected build kind -- see
# _refresh_water_extractor_indicators.
var _water_extractor_range_indicators: Array = []


func setup(world: Node3D, pathing: PathingManager, fog: FogManager) -> void:
	_world = world
	_pathing = pathing
	_fog = fog

func is_build_mode_active() -> bool:
	return _build_mode_active

## Converts a grid cell to the world-space position of its center. Public
## (no leading underscore) since BeltSegment/Extractor/Processor call this
## on their parent (World, which forwards here) to find their own and their
## neighbors' cells.
static func grid_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * GRID_CELL_SIZE, 0.0, cell.y * GRID_CELL_SIZE)

## Converts a world-space position to the grid cell it falls within.
static func world_to_grid(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x / GRID_CELL_SIZE), roundi(pos.z / GRID_CELL_SIZE))

## The belt/extractor/processor/building occupying `cell`, or null if empty.
func get_structure_at(cell: Vector2i) -> Node:
	return _grid_structures.get(cell, null)

## Records that `node` now occupies `cell`, so neighboring structures can
## find it via get_structure_at.
func register_structure(cell: Vector2i, node: Node) -> void:
	_grid_structures[cell] = node

## Signal handler for BuildPalette.toggle_requested: flips build mode and
## updates the palette UI + ghost preview to match.
func toggle_build_mode() -> void:
	_build_mode_active = not _build_mode_active
	_world.build_palette.set_active(_build_mode_active)
	if _build_mode_active:
		_world.build_palette.set_selected_kind(_build_selected_kind)
		if _build_selected_kind == "extractor":
			_show_extractor_range_indicators()
	else:
		clear_ghost()
		_clear_extractor_range_indicators()
		_clear_water_extractor_range_indicators()
		_clear_port_indicators()
		_dragging_place = false

## Signal handler for BuildPalette.kind_selected: switches which structure
## the next placement will be.
func on_build_kind_selected(kind_id: String) -> void:
	_build_selected_kind = kind_id
	_world.build_palette.set_selected_kind(kind_id)
	_update_ghost_validity()
	if kind_id == "extractor":
		_show_extractor_range_indicators()
	else:
		_clear_extractor_range_indicators()
	if kind_id != "water_extractor":
		_clear_water_extractor_range_indicators()
	_refresh_port_indicators()

## Spawns a translucent green disc over every resource node, sized to
## EXTRACTOR_LINK_RADIUS, so the player can see at a glance where an
## extractor can legally be linked instead of trial-and-error placement.
func _show_extractor_range_indicators() -> void:
	_clear_extractor_range_indicators()
	for n in _world.get_tree().get_nodes_in_group("resource_nodes"):
		var indicator := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = EXTRACTOR_LINK_RADIUS
		mesh.bottom_radius = EXTRACTOR_LINK_RADIUS
		mesh.height = 0.04
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.3, 1.0, 0.5, 0.16)
		mesh.material = mat
		indicator.mesh = mesh
		_world.add_child(indicator)
		indicator.global_position = n.global_position + Vector3(0.0, 0.03, 0.0)
		_extractor_range_indicators.append(indicator)

## Removes every extractor-range indicator, e.g. when switching to a
## different build kind or leaving build mode entirely.
func _clear_extractor_range_indicators() -> void:
	for indicator in _extractor_range_indicators:
		if is_instance_valid(indicator):
			indicator.queue_free()
	_extractor_range_indicators.clear()

## Water Extractor's counterpart to _show_extractor_range_indicators, called
## from _update_ghost_position (not toggle_build_mode/on_build_kind_selected
## like the extractor version) since it needs to know where the cursor
## actually is -- water is continuous terrain with no per-instance node list
## to draw a disc over, so this instead re-samples Biomes.is_water_at across
## a small grid of cells around `center_cell` every time the ghost moves.
## Rebuilds from scratch each call; cheap enough at
## WATER_EXTRACTOR_PREVIEW_RADIUS_CELLS' scale that diffing old-vs-new tiles
## would just be extra bookkeeping for no real benefit.
func _refresh_water_extractor_indicators(center_cell: Vector2i) -> void:
	_clear_water_extractor_range_indicators()
	var r := WATER_EXTRACTOR_PREVIEW_RADIUS_CELLS
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cell := center_cell + Vector2i(dx, dy)
			var world_pos := grid_to_world(cell)
			if not Biomes.is_water_at(world_pos.x, world_pos.z):
				continue
			var indicator := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(GRID_CELL_SIZE * 0.85, 0.04, GRID_CELL_SIZE * 0.85)
			var mat := StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(0.3, 0.6, 1.0, 0.35)
			mesh.material = mat
			indicator.mesh = mesh
			_world.add_child(indicator)
			indicator.global_position = world_pos + Vector3(0.0, 0.05, 0.0)
			_water_extractor_range_indicators.append(indicator)

## Removes every water-extractor legal-spot indicator, e.g. when switching to
## a different build kind or leaving build mode entirely.
func _clear_water_extractor_range_indicators() -> void:
	for indicator in _water_extractor_range_indicators:
		if is_instance_valid(indicator):
			indicator.queue_free()
	_water_extractor_range_indicators.clear()

## Rebuilds the port-direction arrows for whatever's currently selected,
## anchored at the ghost's current cell: one per BuildingKinds input/output
## port for a kind that has fixed ports (Town Hall/StorageDepot/WaterTank),
## or a single output arrow (Extractor) / input+output pair (Processor) for
## the two factory pieces whose single `facing` direction is genuinely
## unambiguous. Belt is deliberately excluded -- its fair multi-side input
## (see LinkableBuilding._resolve_fair_input) means "the" input side isn't a
## single direction, and a single arrow would misrepresent that; Wall/Pipe
## have no ports at all. Called on every ghost move (cheap: at most 2-4
## small meshes) rather than only on kind change, so the arrows also track
## the ghost sliding to a new cell.
func _refresh_port_indicators() -> void:
	_clear_port_indicators()
	var anchor := grid_to_world(_build_ghost_cell)
	var kind = BuildingKinds.get_kind(_build_selected_kind)
	if kind and (not kind.input_ports.is_empty() or not kind.output_ports.is_empty()):
		for offset in kind.input_ports:
			_spawn_port_arrow(anchor, offset, false)
		for offset in kind.output_ports:
			_spawn_port_arrow(anchor, offset, true)
	elif _build_selected_kind == "extractor":
		_spawn_port_arrow(anchor, _build_facing, true)
	elif _build_selected_kind == "processor":
		_spawn_port_arrow(anchor, _build_facing, true)
		_spawn_port_arrow(anchor, -_build_facing, false)

## Spawns one translucent arrow at the cell boundary between `anchor` and
## its neighbor in grid direction `offset`, pointing toward the neighbor
## (an output -- material flows out this way) or back toward `anchor` (an
## input -- material flows in this way).
func _spawn_port_arrow(anchor: Vector3, offset: Vector2i, is_output: bool) -> void:
	var arrow := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = PORT_ARROW_SIZE
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = PORT_ARROW_OUTPUT_COLOR if is_output else PORT_ARROW_INPUT_COLOR
	mesh.material = mat
	arrow.mesh = mesh
	_world.add_child(arrow)
	arrow.global_position = anchor + Vector3(offset.x, 0.3, offset.y) * (GRID_CELL_SIZE * 0.5)
	var point_dir := Vector2(offset) if is_output else -Vector2(offset)
	arrow.look_at(arrow.global_position + Vector3(point_dir.x, 0.0, point_dir.y), Vector3.UP)
	_port_indicators.append(arrow)

## Removes every port-direction arrow, e.g. when switching to a different
## build kind, moving the ghost, or leaving build mode entirely.
func _clear_port_indicators() -> void:
	for indicator in _port_indicators:
		if is_instance_valid(indicator):
			indicator.queue_free()
	_port_indicators.clear()

## Routes all input while build mode is active: mouse movement re-positions
## the ghost (and, if a drag-place is in progress, tries to extend it into
## the newly-entered cell), left click places whatever's selected in the
## palette (and starts a drag-place for DRAG_PLACE_KINDS), releasing left
## ends any drag-place in progress, right click demolishes whatever
## structure is under the ghost cell (regardless of which kind is currently
## selected for placement), 'R' rotates the ghost 90 degrees, and Escape
## exits build mode entirely.
func handle_build_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_ghost_position(event.position)
		if _dragging_place:
			_try_drag_place()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				try_place_structure()
				_dragging_place = _build_selected_kind in DRAG_PLACE_KINDS
				_drag_last_cell = _build_ghost_cell
			else:
				_dragging_place = false
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			demolish_at(_build_ghost_cell)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_rotate_ghost()
		elif event.keycode == KEY_ESCAPE:
			toggle_build_mode()

## Called on every mouse-motion event while a drag-place is in progress (see
## handle_build_input): does nothing until the ghost has actually reached a
## new cell (so holding still mid-drag doesn't spam placements), then --
## for Belt specifically -- re-faces the upcoming segment toward the
## direction just traveled from the last-placed cell, so a dragged line
## curves to follow the mouse path instead of every segment keeping
## whatever facing was picked before the drag started, before attempting
## the actual placement. Silently does nothing at cells that aren't valid
## (occupied, unaffordable, ...), same as a single click would.
func _try_drag_place() -> void:
	if _build_ghost_cell == _drag_last_cell:
		return
	if _build_selected_kind == "belt":
		var delta := _build_ghost_cell - _drag_last_cell
		if delta.x != 0:
			_build_facing = Vector2i(signi(delta.x), 0)
		elif delta.y != 0:
			_build_facing = Vector2i(0, signi(delta.y))
		if _build_ghost:
			_build_ghost.look_at(_build_ghost.global_position + Vector3(_build_facing.x, 0.0, _build_facing.y), Vector3.UP)
		_refresh_port_indicators()
	try_place_structure()
	_drag_last_cell = _build_ghost_cell

## Moves the ghost preview to the grid cell under the mouse (raycast against
## the ground plane), creating it on first use, and refreshes whether that
## cell is currently a valid placement.
func _update_ghost_position(screen_pos: Vector2) -> void:
	var hit: Dictionary = _world.raycast(screen_pos, MASK_GROUND)
	if not hit:
		return
	_build_ghost_cell = world_to_grid(hit.position)
	if not _build_ghost:
		_build_ghost = _create_ghost()
	_build_ghost.global_position = grid_to_world(_build_ghost_cell)
	_build_ghost.look_at(_build_ghost.global_position + Vector3(_build_facing.x, 0.0, _build_facing.y), Vector3.UP)
	_update_ghost_validity()
	if _build_selected_kind == "water_extractor":
		_refresh_water_extractor_indicators(_build_ghost_cell)
	_refresh_port_indicators()

## Builds the flat colored tile + direction arrow used as the placement
## ghost, entirely in code (no scene needed for something this simple).
## Color is updated per-frame by _update_ghost_validity; geometry never
## changes, so it's shared across all structure kinds.
func _create_ghost() -> Node3D:
	var ghost := Node3D.new()
	_world.add_child(ghost)

	var tile := MeshInstance3D.new()
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(GRID_CELL_SIZE * 0.9, 0.2, GRID_CELL_SIZE * 0.9)
	_build_ghost_material = StandardMaterial3D.new()
	_build_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_build_ghost_material.albedo_color = GHOST_VALID_COLOR
	tile_mesh.material = _build_ghost_material
	tile.mesh = tile_mesh
	tile.position = Vector3(0.0, 0.1, 0.0)
	ghost.add_child(tile)

	var arrow := MeshInstance3D.new()
	var arrow_mesh := BoxMesh.new()
	arrow_mesh.size = Vector3(0.25, 0.15, 1.2)
	var arrow_mat := StandardMaterial3D.new()
	arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arrow_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	arrow_mesh.material = arrow_mat
	arrow.mesh = arrow_mesh
	arrow.position = Vector3(0.0, 0.25, -0.3)
	ghost.add_child(arrow)

	return ghost

## Rotates the ghost's facing 90 degrees clockwise (grid-relative, not a free
## rotation) and re-orients the preview to match.
func _rotate_ghost() -> void:
	_build_facing = Vector2i(-_build_facing.y, _build_facing.x)
	if _build_ghost:
		_build_ghost.look_at(_build_ghost.global_position + Vector3(_build_facing.x, 0.0, _build_facing.y), Vector3.UP)
	_refresh_port_indicators()

## Recolors the ghost green/red to reflect whether the current cell and
## structure kind could actually be placed right now.
func _update_ghost_validity() -> void:
	if not _build_ghost_material:
		return
	var valid := is_placement_valid(_build_ghost_cell)
	_build_ghost_material.albedo_color = GHOST_VALID_COLOR if valid else GHOST_INVALID_COLOR

## Whether `cell` is a valid target for the currently-selected build kind.
## Every kind (building or factory piece) occupies exactly its own single
## cell -- a building's input/output ports are directions to its
## *neighboring* cells (where a belt goes), not extra cells the building
## itself claims, same as how an Extractor/Processor's single output side
## works with a belt sitting next to it, not inside it. A building kind must
## also be unlocked; an extractor must be within linking range of an actual
## resource node. (Demolishing is a right-click, handled separately in
## handle_build_input -- it isn't a selectable placement kind.)
func is_placement_valid(cell: Vector2i) -> bool:
	var building_kind = BuildingKinds.get_kind(_build_selected_kind)
	if building_kind and not GameManager.is_building_unlocked(_build_selected_kind):
		return false

	if get_structure_at(cell) != null:
		return false

	var world_pos := grid_to_world(cell)
	# Can't build somewhere the player hasn't actually seen yet -- applies
	# to every kind uniformly, checked before any kind-specific rule below.
	if not _fog.is_revealed(world_pos):
		return false

	if _build_selected_kind == "extractor":
		return _find_resource_node_near(world_pos) != null
	if _build_selected_kind == "water_extractor":
		return Biomes.is_water_at(world_pos.x, world_pos.z)
	# Every other kind is a land structure -- Water Extractor above is the
	# one deliberate exception that *requires* water instead of forbidding it.
	if Biomes.is_water_at(world_pos.x, world_pos.z):
		return false
	return true

## Every grid cell `kind_id` occupies if placed with its anchor at `anchor`
## -- always just the anchor itself; a building's ports describe directions
## to its neighboring cells, not additional cells it claims (see
## is_placement_valid). Kept as its own helper (rather than inlining
## `[anchor]`) so demolish/placement code reads the same way regardless of
## kind, and so a genuinely multi-cell building could extend this later.
func _get_footprint_cells(_kind_id: String, anchor: Vector2i) -> Array:
	return [anchor]

## Wood cost of placing `kind_id`, whether it's a building kind (cost lives
## on its BuildingKinds entry) or a factory piece (cost lives in BUILD_COSTS).
func get_build_cost(kind_id: String) -> int:
	var building_kind = BuildingKinds.get_kind(kind_id)
	if building_kind:
		return building_kind.build_cost
	return BUILD_COSTS.get(kind_id, 0)

## Closest resource node within EXTRACTOR_LINK_RADIUS of `pos`, or null.
func _find_resource_node_near(pos: Vector3) -> Node:
	var nearest: Node = null
	var nearest_dist := EXTRACTOR_LINK_RADIUS
	for n in _world.get_tree().get_nodes_in_group("resource_nodes"):
		var d: float = pos.distance_to(n.global_position)
		if d <= nearest_dist:
			nearest_dist = d
			nearest = n
	return nearest

## Attempts to place the currently-selected build kind at the ghost's cell:
## validates placement, spends the wood cost, instantiates and orients the
## real structure, and registers it on the grid. Silently does nothing if
## the action is invalid or unaffordable -- the ghost's color already told
## the player which case they're in. (Demolishing is a separate right-click
## action, see demolish_at.)
func try_place_structure() -> void:
	if not is_placement_valid(_build_ghost_cell):
		return
	var cost := get_build_cost(_build_selected_kind)
	if not GameManager.try_spend_wood(cost):
		return

	var node: Node3D = instantiate_structure(_build_selected_kind)
	# Buildings don't rotate to face a placement direction (their ports are
	# fixed world-relative offsets, see BuildingKinds) -- only factory pieces
	# expose a `facing` property, so this is skipped for them.
	if "facing" in node:
		node.facing = _build_facing
	if "kind_id" in node:
		node.kind_id = _build_selected_kind
	_world.add_child(node)
	node.global_position = grid_to_world(_build_ghost_cell)
	if "facing" in node:
		node.look_at(node.global_position + Vector3(_build_facing.x, 0.0, _build_facing.y), Vector3.UP)

	var footprint := _get_footprint_cells(_build_selected_kind, _build_ghost_cell)
	for cell in footprint:
		register_structure(cell, node)
		if _pathing.structure_blocks_movement(node):
			_pathing.mark_cell(cell, true)
	node.set_meta("build_kind", _build_selected_kind)
	node.set_meta("occupied_cells", footprint)

	if _build_selected_kind == "extractor":
		node.linked_node = _find_resource_node_near(node.global_position)

	refresh_neighbor_visuals(_build_ghost_cell)
	_update_ghost_validity()

## Removes whatever structure occupies `cell` (a right-click in build mode,
## regardless of which kind is currently selected for placement), refunding
## half its original wood cost, freeing any item it was holding (a belt's
## current_item) rather than leaving it orphaned on the grid, clearing every
## grid cell it occupied (not just `cell` itself -- a building spans
## multiple cells, see _get_footprint_cells) and re-opening any pathing
## cells it had closed off. No-ops if `cell` is empty.
func demolish_at(cell: Vector2i) -> void:
	var structure := get_structure_at(cell)
	if structure == null:
		return
	if "current_item" in structure and structure.current_item:
		structure.current_item.queue_free()
	var occupied: Array = structure.get_meta("occupied_cells", [cell])
	var kind: String = structure.get_meta("build_kind", "belt")
	var blocked_movement := _pathing.structure_blocks_movement(structure)
	for occupied_cell in occupied:
		_grid_structures.erase(occupied_cell)
		if blocked_movement:
			_pathing.mark_cell(occupied_cell, false)
	var refund: int = get_build_cost(kind) / 2
	if refund > 0:
		GameManager.add_resource("wood", refund)
	structure.queue_free()
	refresh_neighbor_visuals(cell)
	_update_ghost_validity()

## Asks the structure at `cell` and every structure in the 4 cells around it
## (belts only actually respond -- see BeltSegment.refresh_connections) to
## re-check their neighbors and update which of their side walls are open,
## so a belt chain visually reacts immediately when a new piece is placed
## next to it or an existing one is removed, without needing a full-grid
## rescan. `cell` itself needs this too, not just its neighbors -- a belt's
## _ready() can't do its own initial check (see BeltSegment._ready), since
## World sets its real position/rotation only *after* add_child().
func refresh_neighbor_visuals(cell: Vector2i) -> void:
	var offsets := [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for offset in offsets:
		var neighbor := get_structure_at(cell + offset)
		if neighbor and neighbor.has_method("refresh_connections"):
			neighbor.refresh_connections()

## Instantiates (but does not yet place) the scene for `kind` -- a building
## kind's scene comes from its BuildingKinds entry (this now covers Wall and
## Belt too, see scripts/core/linkable_building.gd), a factory piece's from
## this manager's own preloaded scenes. Extractor/Processor are the only
## kinds left that never joined the tech tree.
func instantiate_structure(kind: String) -> Node3D:
	var building_kind = BuildingKinds.get_kind(kind)
	if building_kind:
		return building_kind.scene.instantiate()
	if kind == "extractor":
		return EXTRACTOR_SCENE.instantiate()
	if kind == "water_extractor":
		return WATER_EXTRACTOR_SCENE.instantiate()
	return PROCESSOR_SCENE.instantiate()

## Removes the ghost preview, e.g. when exiting build mode.
func clear_ghost() -> void:
	if _build_ghost:
		_build_ghost.queue_free()
		_build_ghost = null
		_build_ghost_material = null
