extends Node3D
## Top-level game controller: owns the map's procedural scenery, mouse-driven
## unit selection (click, shift-click, drag-box), and translates right-clicks
## into move/harvest orders for the currently selected blobs.
##
## Effect creation (rings, particles, floating text) is delegated to the
## Effects autoload (Factory pattern, see scripts/effects.gd) rather than
## instantiated by hand here.

# Physics layers (see Project Settings > Layer Names > 3D Physics for labels).
const MASK_GROUND := 1
const MASK_BLOBS := 2
const MASK_RESOURCES := 4

const TREE_SCENE: PackedScene = preload("res://scenes/tree.tscn")
const ROCK_SCENE: PackedScene = preload("res://scenes/rock.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")

const BELT_SCENE: PackedScene = preload("res://scenes/factory/belt_segment.tscn")
const EXTRACTOR_SCENE: PackedScene = preload("res://scenes/factory/extractor.tscn")
const PROCESSOR_SCENE: PackedScene = preload("res://scenes/factory/processor.tscn")

const COLOR_MOVE := Color(0.45, 1.0, 0.55)
const COLOR_HARVEST := Color(1.0, 0.8, 0.25)

# A right-click harvest order spreads selected blobs across same-type nodes
# within this radius of the click, capping how many pile onto any one node,
# so a squad doesn't all crowd (and physically jam) a single tree.
const MAX_HARVEST_SPREAD_RADIUS := 16.0
const MAX_BLOBS_PER_NODE := 2

# -- Procedural scenery generation tuning --
# The map is a square of side 2*MAP_HALF_SIZE (must match the Ground plane
# in world.tscn). Cluster centers are scattered at random angle/distance
# from the building, staying outside BUILDING_SAFE_RADIUS of it.
const MAP_HALF_SIZE := 75.0
const BUILDING_SAFE_RADIUS := 10.0
const CLUSTER_MIN_SEPARATION := 6.0

const TREE_CLUSTER_COUNT := 6
const TREE_CLUSTER_RADIUS_RANGE := Vector2(6.0, 11.0)
const TREE_CLUSTER_COUNT_RANGE := Vector2i(8, 14)

const ROCK_CLUSTER_COUNT := 5
const ROCK_CLUSTER_RADIUS_RANGE := Vector2(5.0, 9.0)
const ROCK_CLUSTER_COUNT_RANGE := Vector2i(5, 9)

# -- Enemy population tuning --
# A lone ambient threat, maintained at a small target count rather than
# growing unbounded: a background check tops the population back up a
# while after something dies, similar to how resource nodes respawn.
const ENEMY_TARGET_COUNT := 3
const ENEMY_SPAWN_MIN_DIST := BUILDING_SAFE_RADIUS + 12.0
const ENEMY_POPULATION_CHECK_INTERVAL := 20.0

# -- Build mode / factory automation tuning --
# Extractors, belts, and processors snap to a square grid so belt chains
# line up edge-to-edge; blobs, trees, and enemies are unaffected and stay
# free-form. See the "BUILD MODE" section below for placement/ghost logic.
const GRID_CELL_SIZE := 2.0
const EXTRACTOR_LINK_RADIUS := 3.0
const BUILD_COSTS := {"belt": 5, "extractor": 25, "processor": 30}
const GHOST_VALID_COLOR := Color(0.3, 1.0, 0.4, 0.55)
const GHOST_INVALID_COLOR := Color(1.0, 0.3, 0.3, 0.55)

@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var hud = $HUD
@onready var selection_box = $HUD/SelectionBox
@onready var building_menu = $BuildingMenu
@onready var build_palette = $BuildPalette

var selected_blobs: Array = []
var _dragging := false
var _drag_start := Vector2.ZERO
var _hovered_blob: Node = null

# Grid cell (Vector2i) -> the belt/extractor/processor placed there. Lets
# each structure look up its neighbors (e.g. "is there a belt in front of
# me to hand this item to?") without needing direct references to each other.
var _grid_structures: Dictionary = {}

var _build_mode_active := false
var _build_selected_kind := "belt"
var _build_facing := Vector2i(1, 0)
var _build_ghost: Node3D = null
var _build_ghost_material: StandardMaterial3D = null
var _build_ghost_cell := Vector2i.ZERO


## Godot lifecycle hook: procedurally scatters several separate tree and
## rock patches across the map, then seeds the ambient enemy population and
## starts the timer that keeps topping it back up. Every other object
## (blobs, buildings, UI) already exists as scene children.
func _ready() -> void:
	_spawn_resource_clusters(TREE_SCENE, TREE_CLUSTER_COUNT, TREE_CLUSTER_RADIUS_RANGE, TREE_CLUSTER_COUNT_RANGE)
	_spawn_resource_clusters(ROCK_SCENE, ROCK_CLUSTER_COUNT, ROCK_CLUSTER_RADIUS_RANGE, ROCK_CLUSTER_COUNT_RANGE)

	for i in ENEMY_TARGET_COUNT:
		_spawn_one_enemy()
	var population_timer := Timer.new()
	population_timer.wait_time = ENEMY_POPULATION_CHECK_INTERVAL
	population_timer.timeout.connect(_maintain_enemy_population)
	add_child(population_timer)
	population_timer.start()

	build_palette.toggle_requested.connect(_toggle_build_mode)
	build_palette.kind_selected.connect(_on_build_kind_selected)


## Spawns one enemy at a random angle/distance from the building, staying
## outside ENEMY_SPAWN_MIN_DIST of it and inside the map edge.
func _spawn_one_enemy() -> void:
	var angle := randf() * TAU
	var dist := randf_range(ENEMY_SPAWN_MIN_DIST, MAP_HALF_SIZE - 10.0)
	var enemy: Node3D = ENEMY_SCENE.instantiate()
	add_child(enemy)
	enemy.global_position = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

## Signal handler for the population-check timer: tops the enemy count back
## up to ENEMY_TARGET_COUNT one at a time (rather than all at once) if
## anything has died since the last check.
func _maintain_enemy_population() -> void:
	if get_tree().get_nodes_in_group("enemies").size() < ENEMY_TARGET_COUNT:
		_spawn_one_enemy()

## Scatters `cluster_count` separate patches of `scene` around the map, each
## with its own randomized position, radius (within `radius_range`) and
## instance count (within `count_range`). This is what gives the map its
## "several patches to discover, further out in every direction" feel,
## rather than one or two fixed blobs of scenery.
func _spawn_resource_clusters(scene: PackedScene, cluster_count: int, radius_range: Vector2, count_range: Vector2i) -> void:
	var placed_centers: Array = []
	for i in cluster_count:
		var radius := randf_range(radius_range.x, radius_range.y)
		var center := _find_cluster_center(radius, placed_centers)
		placed_centers.append(center)
		var count := randi_range(count_range.x, count_range.y)
		_spawn_cluster(scene, center, radius, count)

## Picks a cluster center at a random angle/distance from the building
## (staying outside BUILDING_SAFE_RADIUS of it and inside the map edge),
## retrying a handful of times to also stay clear of previously placed
## clusters so separate patches read as distinct rather than overlapping
## into one another. Falls back to whatever the last attempt found if it
## can't avoid overlap within the retry budget -- still a valid placement,
## just possibly touching a neighboring patch.
func _find_cluster_center(radius: float, existing: Array) -> Vector3:
	var min_dist := BUILDING_SAFE_RADIUS + radius
	var max_dist := MAP_HALF_SIZE - radius - 5.0
	var candidate := Vector3.ZERO
	for attempt in 6:
		var angle := randf() * TAU
		var dist := randf_range(min_dist, max_dist)
		candidate = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var far_enough := true
		for other in existing:
			if candidate.distance_to(other) < radius + CLUSTER_MIN_SEPARATION:
				far_enough = false
				break
		if far_enough:
			break
	return candidate

## Scatters `count` instances of `scene` in a uniform-density disk of
## `radius` around `center`, each with a random facing and a slightly
## randomized scale, so a cluster of trees/rocks looks organic rather than
## like a grid.
func _spawn_cluster(scene: PackedScene, center: Vector3, radius: float, count: int) -> void:
	for i in count:
		var inst: Node3D = scene.instantiate()
		add_child(inst)
		var angle := randf() * TAU
		var r := sqrt(randf()) * radius
		inst.global_position = center + Vector3(cos(angle) * r, 0.0, sin(angle) * r)
		inst.rotation.y = randf() * TAU
		var s := randf_range(0.85, 1.25)
		inst.scale = Vector3(s, s, s)

## Central input router: while build mode is active, every input goes to
## the placement system instead (see _handle_build_input). Otherwise: left
## button drives selection (click vs. drag-box, with shift held meaning
## "add to selection"), right button issues an order to whatever's
## currently selected, and plain mouse motion (while not dragging) drives
## the hover highlight.
func _unhandled_input(event: InputEvent) -> void:
	if _build_mode_active:
		_handle_build_input(event)
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_start = event.position
			else:
				if _dragging:
					if _drag_start.distance_to(event.position) < 6.0:
						_handle_click_select(event.position, event.shift_pressed)
					else:
						_handle_box_select(_drag_start, event.position, event.shift_pressed)
				_dragging = false
				selection_box.hide_rect()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click(event.position)
	elif event is InputEventMouseMotion:
		if _dragging:
			selection_box.show_rect(_drag_start, event.position)
		else:
			_update_hover(event.position)

## Fires a physics ray from the camera through the given screen position and
## returns the first hit whose collision layer matches `mask` (empty
## Dictionary if nothing was hit). Shared by every click/hover check below.
func _raycast(screen_pos: Vector2, mask: int) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = mask
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)

## Handles a plain (non-drag) left click: selects a blob if one was clicked,
## opens the building's upgrade menu if the building was clicked, or clears
## the selection if empty ground was clicked (unless shift/additive is held,
## in which case an empty click does nothing).
func _handle_click_select(pos: Vector2, additive: bool) -> void:
	var hit := _raycast(pos, MASK_BLOBS)
	if hit and hit.collider.is_in_group("blobs"):
		if not additive:
			_clear_selection()
		_select_blob(hit.collider)
		hud.set_selected_count(selected_blobs.size())
		return

	var building_hit := _raycast(pos, MASK_RESOURCES)
	var building_owner = building_hit.collider.get_parent() if building_hit else null
	if building_owner and building_owner.is_in_group("buildings"):
		building_menu.open_menu()
		return

	if not additive:
		_clear_selection()
	hud.set_selected_count(selected_blobs.size())

## Handles a left-click drag: selects every blob whose on-screen projected
## position falls inside the dragged rectangle (skipping any blob currently
## behind the camera, which would otherwise project to a bogus screen point).
func _handle_box_select(a: Vector2, b: Vector2, additive: bool) -> void:
	if not additive:
		_clear_selection()
	var rect := Rect2(a, Vector2.ZERO).expand(b)
	for blob in get_tree().get_nodes_in_group("blobs"):
		var to_blob: Vector3 = blob.global_position - camera.global_position
		if camera.global_transform.basis.z.dot(to_blob) > 0.0:
			continue
		var screen_pos := camera.unproject_position(blob.global_position)
		if rect.has_point(screen_pos):
			_select_blob(blob)
	hud.set_selected_count(selected_blobs.size())

## Updates which blob (if any) is under the mouse cursor and toggles its
## hover highlight, clearing the previous hover target first. Only called
## while the player isn't drag-selecting.
func _update_hover(pos: Vector2) -> void:
	var hit := _raycast(pos, MASK_BLOBS)
	var hovered = hit.collider if hit and hit.collider.is_in_group("blobs") else null
	if hovered == _hovered_blob:
		return
	if is_instance_valid(_hovered_blob):
		_hovered_blob.set_hovered(false)
	_hovered_blob = hovered
	if is_instance_valid(_hovered_blob):
		_hovered_blob.set_hovered(true)

## Handles a right-click: does nothing if no blobs are selected, otherwise
## issues a harvest order (if a resource node was clicked) or a plain move
## order (if empty ground was clicked) to the whole selection, and spawns a
## ring marker at the target to confirm the order was accepted.
func _handle_right_click(pos: Vector2) -> void:
	# A selected blob may have died (enemy combat) since it was selected;
	# drop any stale references before issuing commands to the selection.
	selected_blobs = selected_blobs.filter(is_instance_valid)
	if selected_blobs.is_empty():
		return
	var hit := _raycast(pos, MASK_RESOURCES | MASK_GROUND)
	if not hit:
		return
	if hit.collider.is_in_group("resource_nodes"):
		_issue_harvest_orders(hit.collider)
		Effects.spawn_command_marker(self, hit.collider.global_position + Vector3(0.0, 0.05, 0.0), COLOR_HARVEST)
	else:
		for blob in selected_blobs:
			blob.command_move(hit.position)
		Effects.spawn_command_marker(self, hit.position + Vector3(0.0, 0.05, 0.0), COLOR_MOVE)

## Assigns each selected blob to a nearby node of the same resource type as
## `clicked_node`, spreading the squad across up to MAX_BLOBS_PER_NODE nodes
## within MAX_HARVEST_SPREAD_RADIUS instead of sending everyone to the exact
## node clicked. Each blob picks its own closest still-available node, and
## gets a deterministic (evenly-spaced) approach angle around it so two
## blobs assigned to the same node don't both aim for the same spot and jam
## each other. Falls back to piling everyone onto the closest candidate if
## every nearby node of that type is already at capacity.
func _issue_harvest_orders(clicked_node: Node) -> void:
	var target_type: String = clicked_node.resource_type
	var origin: Vector3 = clicked_node.global_position

	var candidates: Array = []
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		if n.resource_type == target_type and n.global_position.distance_to(origin) <= MAX_HARVEST_SPREAD_RADIUS:
			candidates.append(n)
	if candidates.is_empty():
		candidates.append(clicked_node)

	var assigned_count: Dictionary = {}
	for blob in selected_blobs:
		var best_node: Node = null
		var best_dist := INF
		for n in candidates:
			if assigned_count.get(n, 0) >= MAX_BLOBS_PER_NODE:
				continue
			var d: float = blob.global_position.distance_to(n.global_position)
			if d < best_dist:
				best_dist = d
				best_node = n
		if best_node == null:
			# Every nearby node of this type is already fully assigned; pile onto the closest one anyway.
			for n in candidates:
				var d: float = blob.global_position.distance_to(n.global_position)
				if d < best_dist:
					best_dist = d
					best_node = n
		if best_node:
			var slot: int = assigned_count.get(best_node, 0)
			assigned_count[best_node] = slot + 1
			var angle := (TAU / MAX_BLOBS_PER_NODE) * slot
			blob.command_harvest(best_node, angle)

## Adds `blob` to the current selection (no-op if already selected) and
## turns on its selection ring.
func _select_blob(blob: Node) -> void:
	if selected_blobs.has(blob):
		return
	selected_blobs.append(blob)
	blob.set_selected(true)

## Deselects every currently-selected blob and empties the selection.
func _clear_selection() -> void:
	for blob in selected_blobs:
		if is_instance_valid(blob):
			blob.set_selected(false)
	selected_blobs.clear()


# ============================================================================
# BUILD MODE -- placing extractors, processors, and conveyor belts on a grid.
#
# Structures register themselves into `_grid_structures` (via
# register_structure) so a belt/extractor/processor can look up "what's in
# the cell I'm facing" (via get_structure_at) without holding direct
# references to each other -- that's what lets a chain of independently-
# placed belts hand items down the line.
# ============================================================================

## Converts a grid cell to the world-space position of its center. Public
## (no leading underscore) since BeltSegment/Extractor/Processor call this
## on their parent (this node) to find their own and their neighbors' cells.
func grid_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * GRID_CELL_SIZE, 0.0, cell.y * GRID_CELL_SIZE)

## Converts a world-space position to the grid cell it falls within.
func world_to_grid(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x / GRID_CELL_SIZE), roundi(pos.z / GRID_CELL_SIZE))

## The belt/extractor/processor occupying `cell`, or null if empty.
func get_structure_at(cell: Vector2i) -> Node:
	return _grid_structures.get(cell, null)

## Records that `node` now occupies `cell`, so neighboring structures can
## find it via get_structure_at.
func register_structure(cell: Vector2i, node: Node) -> void:
	_grid_structures[cell] = node

## Signal handler for BuildPalette.toggle_requested: flips build mode and
## updates the palette UI + ghost preview to match.
func _toggle_build_mode() -> void:
	_build_mode_active = not _build_mode_active
	build_palette.set_active(_build_mode_active)
	if _build_mode_active:
		build_palette.set_selected_kind(_build_selected_kind)
	else:
		_clear_ghost()

## Signal handler for BuildPalette.kind_selected: switches which structure
## the next placement will be.
func _on_build_kind_selected(kind_id: String) -> void:
	_build_selected_kind = kind_id
	build_palette.set_selected_kind(kind_id)
	_update_ghost_validity()

## Routes all input while build mode is active: mouse movement re-positions
## the ghost, left click places, right click or 'R' rotates the ghost 90
## degrees, and Escape exits build mode entirely.
func _handle_build_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_ghost_position(event.position)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_place_structure()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_rotate_ghost()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_rotate_ghost()
		elif event.keycode == KEY_ESCAPE:
			_toggle_build_mode()

## Moves the ghost preview to the grid cell under the mouse (raycast
## against the ground plane), creating it on first use, and refreshes
## whether that cell is currently a valid placement.
func _update_ghost_position(screen_pos: Vector2) -> void:
	var hit := _raycast(screen_pos, MASK_GROUND)
	if not hit:
		return
	_build_ghost_cell = world_to_grid(hit.position)
	if not _build_ghost:
		_build_ghost = _create_ghost()
	_build_ghost.global_position = grid_to_world(_build_ghost_cell)
	_build_ghost.look_at(_build_ghost.global_position + Vector3(_build_facing.x, 0.0, _build_facing.y), Vector3.UP)
	_update_ghost_validity()

## Builds the flat colored tile + direction arrow used as the placement
## ghost, entirely in code (no scene needed for something this simple).
## Color is updated per-frame by _update_ghost_validity; geometry never
## changes, so it's shared across all three structure kinds.
func _create_ghost() -> Node3D:
	var ghost := Node3D.new()
	add_child(ghost)

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

## Rotates the ghost's facing 90 degrees clockwise (grid-relative, not a
## free rotation) and re-orients the preview to match.
func _rotate_ghost() -> void:
	_build_facing = Vector2i(-_build_facing.y, _build_facing.x)
	if _build_ghost:
		_build_ghost.look_at(_build_ghost.global_position + Vector3(_build_facing.x, 0.0, _build_facing.y), Vector3.UP)

## Recolors the ghost green/red to reflect whether the current cell and
## structure kind could actually be placed right now.
func _update_ghost_validity() -> void:
	if not _build_ghost_material:
		return
	var valid := _is_placement_valid(_build_ghost_cell)
	_build_ghost_material.albedo_color = GHOST_VALID_COLOR if valid else GHOST_INVALID_COLOR

## Whether `cell` is free to place the currently-selected structure kind:
## must be unoccupied, clear of the building's own footprint, and -- for an
## extractor specifically -- within linking range of an actual resource node.
func _is_placement_valid(cell: Vector2i) -> bool:
	if get_structure_at(cell) != null:
		return false
	if grid_to_world(cell).length() < BUILDING_SAFE_RADIUS * 0.6:
		return false
	if _build_selected_kind == "extractor":
		return _find_resource_node_near(grid_to_world(cell)) != null
	return true

## Closest resource node within EXTRACTOR_LINK_RADIUS of `pos`, or null.
func _find_resource_node_near(pos: Vector3) -> Node:
	var nearest: Node = null
	var nearest_dist := EXTRACTOR_LINK_RADIUS
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var d: float = pos.distance_to(n.global_position)
		if d <= nearest_dist:
			nearest_dist = d
			nearest = n
	return nearest

## Attempts to place the currently-selected structure kind at the ghost's
## cell: validates placement, spends the wood cost, instantiates and
## orients the real structure, and registers it on the grid. Silently does
## nothing if the placement is invalid or unaffordable -- the ghost's color
## already told the player which case they're in.
func _try_place_structure() -> void:
	if not _is_placement_valid(_build_ghost_cell):
		return
	var cost: int = BUILD_COSTS.get(_build_selected_kind, 0)
	if not GameManager.try_spend_wood(cost):
		return

	var node: Node3D = _instantiate_structure(_build_selected_kind)
	node.facing = _build_facing
	add_child(node)
	node.global_position = grid_to_world(_build_ghost_cell)
	node.look_at(node.global_position + Vector3(_build_facing.x, 0.0, _build_facing.y), Vector3.UP)
	register_structure(_build_ghost_cell, node)

	if _build_selected_kind == "extractor":
		node.linked_node = _find_resource_node_near(node.global_position)

	_update_ghost_validity()

## Instantiates (but does not yet place) the scene for `kind`.
func _instantiate_structure(kind: String) -> Node3D:
	match kind:
		"extractor":
			return EXTRACTOR_SCENE.instantiate()
		"processor":
			return PROCESSOR_SCENE.instantiate()
		_:
			return BELT_SCENE.instantiate()

## Removes the ghost preview, e.g. when exiting build mode.
func _clear_ghost() -> void:
	if _build_ghost:
		_build_ghost.queue_free()
		_build_ghost = null
		_build_ghost_material = null
