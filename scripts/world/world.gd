extends Node3D
## Top-level game controller: owns the map's procedural scenery, mouse-driven
## unit selection (click, shift-click, drag-box), and translates right-clicks
## into move/harvest orders for the currently selected blobs.
##
## Effect creation (rings, particles, floating text) is delegated to the
## Effects autoload (Factory pattern, see scripts/autoload/effects.gd) rather than
## instantiated by hand here.

# Physics layers (see Project Settings > Layer Names > 3D Physics for labels).
const MASK_GROUND := 1
const MASK_BLOBS := 2
const MASK_RESOURCES := 4

const ENEMY_SCENE: PackedScene = preload("res://scenes/units/enemy/enemy.tscn")
const BLOB_SCENE: PackedScene = preload("res://scenes/units/blob/blob.tscn")

const BELT_SCENE: PackedScene = preload("res://scenes/factory/belt_segment.tscn")
const EXTRACTOR_SCENE: PackedScene = preload("res://scenes/factory/extractor.tscn")
const PROCESSOR_SCENE: PackedScene = preload("res://scenes/factory/processor.tscn")
const WALL_SCENE: PackedScene = preload("res://scenes/factory/wall.tscn")

const COLOR_MOVE := Color(0.45, 1.0, 0.55)
const COLOR_HARVEST := Color(1.0, 0.8, 0.25)
const COLOR_PATROL := Color(0.4, 0.7, 1.0)

# A right-click harvest order spreads selected blobs across same-type nodes
# within this radius of the click, capping how many pile onto any one node,
# so a squad doesn't all crowd (and physically jam) a single tree.
const MAX_HARVEST_SPREAD_RADIUS := 16.0
const MAX_BLOBS_PER_NODE := 2

# -- Gathering tools (see Blob.equipped_item / _order_equip) --
# Animals (food) and water sources are only harvestable by a blob carrying
# the matching tool -- everything else (wood/stone/mushroom/...) stays
# unrestricted, same as it always was.
const ITEM_REQUIRED_FOR_RESOURCE := {"food": "weapon", "water": "bucket"}
const EQUIP_COST := 10

# -- Founder crew --
# There's no building at game start (see the BUILD MODE section) -- the
# player has to construct the Town Hall themselves. These few blobs exist
# so there's something to select and command before that happens, spawned
# directly by World rather than by any Building.
const FOUNDER_BLOB_COUNT := 3
const FOUNDER_SPAWN_RADIUS := 2.0

# -- Chunk streaming (see scripts/world/chunk.gd) --
# The world is tiled into Chunk-sized squares that generate their ground/
# scenery the first time the camera comes near them (Minecraft-style
# loading), keyed by Vector2i chunk coordinate. Deliberately load-only --
# see Chunk's header for why chunks are never unloaded once generated.
const CHUNK_LOAD_RADIUS := 3
const CHUNK_CHECK_INTERVAL := 0.5

# Half-size used for the minimap's world<->local mapping and the
# pathfinding grid's bounds -- not a hard map edge (chunks stream in
# however far the camera can reach), just a generous fixed scale for both.
const MINIMAP_HALF_SIZE := 90.0
const PATHING_GRID_HALF_SIZE := 90.0

# -- Enemy population tuning --
# A lone ambient threat, maintained at a small target count rather than
# growing unbounded: a background check tops the population back up a
# while after something dies, similar to how resource nodes respawn. Each
# spawn picks a random *already-loaded* chunk and an enemy kind from that
# chunk's biome (see Biomes), so kind and difficulty stay biome-appropriate.
const ENEMY_TARGET_COUNT := 3
const ENEMY_POPULATION_CHECK_INTERVAL := 20.0

# -- Build mode / factory automation tuning --
# Extractors, belts, processors, and walls snap to a square grid so belt
# chains line up edge-to-edge; blobs, trees, and enemies are unaffected and
# stay free-form. See the "BUILD MODE" section below for placement/ghost
# logic. Belts are deliberately walkable (not in NON_BLOCKING_KINDS'
# complement below) -- see _kind_blocks_movement.
const GRID_CELL_SIZE := 2.0
const EXTRACTOR_LINK_RADIUS := 3.0
const BUILD_COSTS := {"belt": 5, "extractor": 25, "processor": 30, "wall": 8}
const GHOST_VALID_COLOR := Color(0.3, 1.0, 0.4, 0.55)
const GHOST_INVALID_COLOR := Color(1.0, 0.3, 0.3, 0.55)

@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var camera_rig: Node3D = $CameraRig
@onready var hud = $HUD
@onready var selection_box = $HUD/SelectionBox
@onready var building_menu = $BuildingMenu
@onready var build_palette = $BuildPalette
@onready var debug_menu = $DebugMenu
@onready var unit_info_panel = $UnitInfoPanel
@onready var minimap = $Minimap/Display
@onready var resource_info_panel = $ResourceInfoPanel

var selected_blobs: Array = []
var _dragging := false
var _drag_start := Vector2.ZERO
var _hovered_blob: Node = null

# Set by pressing P with blobs selected; the *next* right-click sets the
# patrol's far point instead of issuing a normal move/harvest order (see
# _handle_right_click). Hold ("H") and Explore ("X") take effect
# immediately with no follow-up click needed.
var _pending_patrol := false

# Grid cell (Vector2i) -> the belt/extractor/processor placed there. Lets
# each structure look up its neighbors (e.g. "is there a belt in front of
# me to hand this item to?") without needing direct references to each other.
var _grid_structures: Dictionary = {}

# Chunk coordinate (Vector2i) -> the generated Chunk node there. See
# scripts/world/chunk.gd and _ensure_chunks_loaded.
var _loaded_chunks: Dictionary = {}
var _chunk_check_timer := 0.0

# Grid-based A* used so blobs/enemies route *around* walls/buildings/
# extractors/processors instead of just locally jittering against them
# (belts stay walkable, see _kind_blocks_movement). Rebuilt as a flat plane
# once at startup; individual cells go solid/clear as structures are
# placed/demolished (see _mark_pathing_cell).
var _pathing_grid := AStarGrid2D.new()

var _build_mode_active := false
var _build_selected_kind := "belt"
var _build_facing := Vector2i(1, 0)
var _build_ghost: Node3D = null
var _build_ghost_material: StandardMaterial3D = null
var _build_ghost_cell := Vector2i.ZERO

# Translucent discs shown over every resource node while "extractor" is the
# selected build kind, so the player can see valid linking range at a
# glance instead of guessing and getting an invalid-placement red ghost.
var _extractor_range_indicators: Array = []

var _debug_menu_active := false
# Whether DebugMenu's "Toggle Hitboxes" overlay (collision shapes + attack/
# detection/link ranges, attached as temporary child nodes tagged
# "debug_visual_nodes") is currently shown.
var _debug_visuals_active := false

# Whether DebugMenu's "Toggle Grid" overlay (a static line-mesh showing the
# factory-placement grid's cell boundaries) is currently shown; the overlay
# node itself is built lazily on first toggle-on, then just shown/hidden.
var _grid_overlay_active := false
var _grid_overlay: MeshInstance3D = null


## Godot lifecycle hook: sets up the pathing grid, streams in the chunks
## around the origin (where founder blobs start and the player will likely
## build first), seeds the ambient enemy population and starts the timer
## that keeps topping it back up. Every other object (blobs, buildings, UI)
## already exists as scene children.
func _ready() -> void:
	minimap.set_world_bounds(MINIMAP_HALF_SIZE)
	_setup_pathing_grid()
	_spawn_founder_blobs()
	_ensure_chunks_loaded(Vector3.ZERO)

	for i in ENEMY_TARGET_COUNT:
		_spawn_one_enemy()
	var population_timer := Timer.new()
	population_timer.wait_time = ENEMY_POPULATION_CHECK_INTERVAL
	population_timer.timeout.connect(_maintain_enemy_population)
	add_child(population_timer)
	population_timer.start()

	build_palette.toggle_requested.connect(_toggle_build_mode)
	build_palette.kind_selected.connect(_on_build_kind_selected)

	debug_menu.toggle_requested.connect(_toggle_debug_menu)
	debug_menu.spawn_blob_requested.connect(_debug_spawn_blob)
	debug_menu.spawn_enemy_requested.connect(_spawn_one_enemy)
	debug_menu.add_resources_requested.connect(_debug_add_resources)
	debug_menu.toggle_hitboxes_requested.connect(_toggle_debug_visuals)
	debug_menu.toggle_grid_requested.connect(_toggle_world_grid)

	unit_info_panel.patrol_requested.connect(_order_pending_patrol)
	unit_info_panel.hold_requested.connect(_order_hold)
	unit_info_panel.explore_requested.connect(_order_explore)
	unit_info_panel.equip_weapon_requested.connect(func(): _order_equip("weapon"))
	unit_info_panel.equip_bucket_requested.connect(func(): _order_equip("bucket"))

## Godot per-frame hook: periodically (not every frame -- see
## CHUNK_CHECK_INTERVAL) makes sure every chunk within CHUNK_LOAD_RADIUS of
## the camera's current focus point has been generated.
func _process(delta: float) -> void:
	_chunk_check_timer -= delta
	if _chunk_check_timer <= 0.0:
		_chunk_check_timer = CHUNK_CHECK_INTERVAL
		_ensure_chunks_loaded(camera_rig.position)

## Spawns the player's starting crew directly (not via any Building, since
## none exists yet -- the player has to construct the Town Hall themselves
## via Build Mode) at the map origin, evenly spaced in a small ring.
func _spawn_founder_blobs() -> void:
	for i in FOUNDER_BLOB_COUNT:
		var angle := (TAU / FOUNDER_BLOB_COUNT) * i
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * FOUNDER_SPAWN_RADIUS
		var blob: Node3D = BLOB_SCENE.instantiate()
		blob.kind_id = "worker"
		add_child(blob)
		blob.global_position = offset
		blob.play_spawn_pop()

## Spawns one enemy at a random point within a random already-loaded chunk,
## picking one of that chunk's biome's enemy kinds (see Biomes/EnemyKinds)
## so both difficulty and flavor stay appropriate to where it lands -- a
## chunk near the origin is always "plains" (slime only), so the immediate
## starting area never spawns the tougher outer-biome kinds.
func _spawn_one_enemy() -> void:
	if _loaded_chunks.is_empty():
		return
	var chunk: Chunk = _loaded_chunks.values().pick_random()
	var kind_id: String = chunk.biome.enemy_kind_ids.pick_random()
	var half := Chunk.CHUNK_SIZE * 0.5
	var enemy: Node3D = ENEMY_SCENE.instantiate()
	enemy.kind_id = kind_id
	add_child(enemy)
	enemy.global_position = chunk.global_position + Vector3(randf_range(-half, half), 0.0, randf_range(-half, half))

## Signal handler for the population-check timer: tops the enemy count back
## up to ENEMY_TARGET_COUNT one at a time (rather than all at once) if
## anything has died since the last check.
func _maintain_enemy_population() -> void:
	if get_tree().get_nodes_in_group("enemies").size() < ENEMY_TARGET_COUNT:
		_spawn_one_enemy()

## Signal handler for DebugMenu.toggle_requested.
func _toggle_debug_menu() -> void:
	_debug_menu_active = not _debug_menu_active
	debug_menu.set_active(_debug_menu_active)

## Signal handler for DebugMenu's "Generate Blob" button: asks the nearest
## building to spawn a free blob.
func _debug_spawn_blob() -> void:
	var building = get_tree().get_first_node_in_group("buildings")
	if building:
		building.debug_spawn_blob()

## Signal handler for DebugMenu's "Add Resources" button: tops up every
## known resource type by 100.
func _debug_add_resources() -> void:
	GameManager.add_resource("wood", 100)
	GameManager.add_resource("stone", 100)
	GameManager.add_resource("planks", 100)

## Signal handler for DebugMenu's "Show/Hide Grid" button: toggles a static
## overlay of the factory-placement grid's cell boundaries (built once, on
## first use, then just shown/hidden) -- handy while lining up belt chains.
func _toggle_world_grid() -> void:
	_grid_overlay_active = not _grid_overlay_active
	debug_menu.set_grid_active(_grid_overlay_active)
	if _grid_overlay_active and _grid_overlay == null:
		_grid_overlay = _build_grid_overlay()
		add_child(_grid_overlay)
	if _grid_overlay:
		_grid_overlay.visible = _grid_overlay_active

## Builds a line-mesh grid spanning PATHING_GRID_HALF_SIZE (the same fixed,
## generous bounds the pathing grid and minimap use) at GRID_CELL_SIZE
## spacing, offset by half a cell so lines fall on cell *boundaries* rather
## than through structure centers.
func _build_grid_overlay() -> MeshInstance3D:
	var half := PATHING_GRID_HALF_SIZE
	var cell_count := int(half / GRID_CELL_SIZE)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for i in range(-cell_count, cell_count + 1):
		var offset: float = i * GRID_CELL_SIZE - GRID_CELL_SIZE * 0.5
		st.add_vertex(Vector3(offset, 0.03, -half))
		st.add_vertex(Vector3(offset, 0.03, half))
		st.add_vertex(Vector3(-half, 0.03, offset))
		st.add_vertex(Vector3(half, 0.03, offset))

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.18)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	mesh_inst.material_override = mat
	return mesh_inst

## Signal handler for DebugMenu's "Show/Hide Hitboxes" button: spawns (or
## clears) translucent collision-shape and attack/detection/link-range
## overlays on every currently-existing blob/enemy/resource node/structure.
## A one-time snapshot rather than a continuous overlay -- anything spawned
## *after* toggling on won't get one until toggled off and back on, which
## is an acceptable simplification for a debug-only tool.
func _toggle_debug_visuals() -> void:
	_debug_visuals_active = not _debug_visuals_active
	debug_menu.set_hitboxes_active(_debug_visuals_active)
	if _debug_visuals_active:
		_spawn_debug_visuals()
	else:
		_clear_debug_visuals()

## Attaches range-ring + collision-hitbox overlay children to every relevant
## live object. Overlays are children of their owner (so they move/rotate
## with it for free and get cleaned up automatically if the owner dies)
## rather than tracked in a separate array; _clear_debug_visuals finds them
## all again via their shared "debug_visual_nodes" group.
func _spawn_debug_visuals() -> void:
	_clear_debug_visuals()
	for blob in get_tree().get_nodes_in_group("blobs"):
		_attach_range_ring(blob, blob.ATTACK_RANGE, Color(1.0, 0.3, 0.3, 0.35))
	for enemy in get_tree().get_nodes_in_group("enemies"):
		_attach_range_ring(enemy, enemy.ATTACK_RANGE, Color(1.0, 0.3, 0.3, 0.35))
		_attach_range_ring(enemy, enemy.DETECTION_RANGE, Color(1.0, 0.9, 0.2, 0.2))
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		_attach_range_ring(n, EXTRACTOR_LINK_RADIUS, Color(0.3, 1.0, 0.5, 0.18))
	for group_name in ["blobs", "enemies", "structures", "buildings"]:
		for n in get_tree().get_nodes_in_group(group_name):
			_attach_hitbox_markers(n)

## Adds a flat translucent ring of the given `radius`/`color` as a child of
## `target`, used to visualize an attack/detection/link range at a glance.
func _attach_range_ring(target: Node3D, radius: float, color: Color) -> void:
	if radius <= 0.0:
		return
	var mesh_inst := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = max(radius - 0.06, 0.01)
	mesh.outer_radius = radius
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mesh.material = mat
	mesh_inst.mesh = mesh
	mesh_inst.add_to_group("debug_visual_nodes")
	target.add_child(mesh_inst)
	mesh_inst.position = Vector3(0.0, 0.05, 0.0)

## Adds a translucent wireframe-ish mesh matching each of `target`'s
## CollisionShape3D children, parented to the shape itself so its position
## automatically matches without any extra transform bookkeeping.
func _attach_hitbox_markers(target: Node3D) -> void:
	for child in target.get_children():
		if not (child is CollisionShape3D) or child.shape == null:
			continue
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 1.0, 0.2, 0.25)
		var mesh: Mesh = null
		if child.shape is SphereShape3D:
			var m := SphereMesh.new()
			m.radius = child.shape.radius
			m.height = child.shape.radius * 2.0
			mesh = m
		elif child.shape is BoxShape3D:
			var m := BoxMesh.new()
			m.size = child.shape.size
			mesh = m
		elif child.shape is CylinderShape3D:
			var m := CylinderMesh.new()
			m.top_radius = child.shape.radius
			m.bottom_radius = child.shape.radius
			m.height = child.shape.height
			mesh = m
		if mesh == null:
			continue
		mesh.material = mat
		var vis := MeshInstance3D.new()
		vis.mesh = mesh
		vis.add_to_group("debug_visual_nodes")
		child.add_child(vis)

## Removes every debug-visual overlay node, e.g. when toggling the overlay
## off or refreshing it.
func _clear_debug_visuals() -> void:
	for n in get_tree().get_nodes_in_group("debug_visual_nodes"):
		if is_instance_valid(n):
			n.queue_free()

# ============================================================================
# CHUNK STREAMING -- Minecraft-style "generate as the camera approaches"
# world tiling. See scripts/world/chunk.gd for what a chunk actually builds.
# ============================================================================

## World-space position -> the chunk coordinate containing it.
func _world_pos_to_chunk_coord(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / Chunk.CHUNK_SIZE), floori(pos.z / Chunk.CHUNK_SIZE))

## Chunk coordinate -> the world-space position of its center.
func _chunk_center_world(coord: Vector2i) -> Vector3:
	return Vector3((coord.x + 0.5) * Chunk.CHUNK_SIZE, 0.0, (coord.y + 0.5) * Chunk.CHUNK_SIZE)

## Generates every chunk within CHUNK_LOAD_RADIUS of `around_world_pos` that
## isn't already loaded. Cheap to call repeatedly -- a no-op dictionary
## lookup for every chunk that already exists, real generation work only
## for genuinely new ones.
func _ensure_chunks_loaded(around_world_pos: Vector3) -> void:
	var center_coord := _world_pos_to_chunk_coord(around_world_pos)
	for dy in range(-CHUNK_LOAD_RADIUS, CHUNK_LOAD_RADIUS + 1):
		for dx in range(-CHUNK_LOAD_RADIUS, CHUNK_LOAD_RADIUS + 1):
			var coord := center_coord + Vector2i(dx, dy)
			if not _loaded_chunks.has(coord):
				_generate_chunk(coord)

## Instantiates, positions, and generates the chunk at `coord`, picking its
## biome from its world-space center (see Biomes.biome_for_world_pos).
func _generate_chunk(coord: Vector2i) -> void:
	var center := _chunk_center_world(coord)
	var biome := Biomes.biome_for_world_pos(center)
	var chunk := Chunk.new()
	add_child(chunk)
	chunk.position = center
	chunk.generate(coord, biome)
	_loaded_chunks[coord] = chunk


# ============================================================================
# PATHING GRID -- grid-based A* (AStarGrid2D) so blobs/enemies route around
# walls/buildings/extractors/processors instead of only locally jittering
# against them (see Blob._compute_path / _advance_along_path). Belts stay
# walkable, matching their existing "low structures, not obstacles" design.
# ============================================================================

## Builds the pathing grid as one big walkable plane; individual cells go
## solid as blocking structures are placed (see _mark_pathing_cell).
func _setup_pathing_grid() -> void:
	var half := int(PATHING_GRID_HALF_SIZE / GRID_CELL_SIZE)
	_pathing_grid.region = Rect2i(-half, -half, half * 2, half * 2)
	_pathing_grid.cell_size = Vector2(GRID_CELL_SIZE, GRID_CELL_SIZE)
	_pathing_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	_pathing_grid.update()

## Marks `cell` solid/clear in the pathing grid, e.g. when a wall/building
## is placed or demolished. No-ops silently if `cell` falls outside the
## grid's bounds (some structure placed right at the edge of reach).
func _mark_pathing_cell(cell: Vector2i, solid: bool) -> void:
	if _pathing_grid.is_in_boundsv(cell):
		_pathing_grid.set_point_solid(cell, solid)

## Whether `kind_id` should block pathing at all -- every placeable kind
## does except belts, which are deliberately walkable (blobs cross them
## like any other patch of ground rather than routing around).
func _kind_blocks_movement(kind_id: String) -> bool:
	return kind_id != "belt"

## Computes a waypoint path (world positions) from `from` to `to` around
## any solid pathing cells in the way, or an empty array if the straight
## line between them is already clear -- callers should just walk directly
## toward `to` in that case rather than hopping through unnecessary
## grid-cell waypoints, keeping normal unobstructed movement smooth instead
## of visibly grid-snapped. Returns an empty array (meaning "just go
## straight and hope for the best") if `to` itself is out of bounds/solid,
## or if no path exists at all -- Blob's existing stall-detector/detour
## system is still there as a fallback for whatever this can't resolve.
func compute_path(from: Vector3, to: Vector3) -> Array:
	if _has_clear_line(from, to):
		return []
	var from_cell := world_to_grid(from)
	var to_cell := world_to_grid(to)
	if not _pathing_grid.is_in_boundsv(from_cell) or not _pathing_grid.is_in_boundsv(to_cell):
		return []
	if _pathing_grid.is_point_solid(to_cell):
		return []
	var cell_path: Array = _pathing_grid.get_id_path(from_cell, to_cell)
	var waypoints: Array = []
	for cell in cell_path:
		waypoints.append(grid_to_world(cell))
	return waypoints

## Samples points along the straight line from `from` to `to` and checks
## whether any of them fall in a solid pathing cell -- used to skip
## grid-based pathing entirely for the common case where nothing's in the way.
func _has_clear_line(from: Vector3, to: Vector3) -> bool:
	var dist := from.distance_to(to)
	var steps := maxi(1, ceili(dist / (GRID_CELL_SIZE * 0.5)))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := from.lerp(to, t)
		var cell := world_to_grid(p)
		if _pathing_grid.is_in_boundsv(cell) and _pathing_grid.is_point_solid(cell):
			return false
	return true

## Central input router: while build mode is active, every input goes to
## the placement system instead (see _handle_build_input). Otherwise: left
## button drives selection (click vs. drag-box, with shift held meaning
## "add to selection"), right button issues an order to whatever's
## currently selected, and plain mouse motion (while not dragging) drives
## the hover highlight.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		_toggle_build_mode()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and building_menu.visible:
		# A right-click anywhere -- not just on another building -- dismisses
		# the open "This Building" info modal instead of falling through to
		# a move/harvest order (or, in build mode, a demolish) behind it.
		building_menu.close_menu()
		return
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
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_order_key(event.keycode)

## Handles the standing-order keyboard shortcuts (P/H/X), no-ops if nothing
## is selected. Delegates to the same _order_* methods UnitInfoPanel's
## standing-order buttons call, so keyboard and UI stay in lockstep.
func _handle_order_key(keycode: int) -> void:
	if selected_blobs.is_empty():
		return
	match keycode:
		KEY_P:
			_order_pending_patrol()
		KEY_H:
			_order_hold()
		KEY_X:
			_order_explore()

## Arms "pending patrol" for the current selection -- the *next* right-click
## sets the far point (see _handle_right_click). Shared by the 'P' key and
## UnitInfoPanel's Patrol button.
func _order_pending_patrol() -> void:
	if selected_blobs.is_empty():
		return
	_pending_patrol = true
	var origin: Vector3 = selected_blobs[0].global_position
	Effects.spawn_floating_text(self, origin + Vector3(0.0, 1.6, 0.0), "Patrol: right-click far point", COLOR_PATROL)

## Orders every currently-selected blob to Hold at its own current position.
## Shared by the 'H' key and UnitInfoPanel's Hold button.
func _order_hold() -> void:
	for blob in selected_blobs:
		blob.command_hold()

## Orders every currently-selected blob to Explore around its own current
## position. Shared by the 'X' key and UnitInfoPanel's Explore button.
func _order_explore() -> void:
	for blob in selected_blobs:
		blob.command_explore()

## Equips every currently-selected blob that doesn't already have `item`
## ("weapon" or "bucket") with it, spending EQUIP_COST wood per blob
## actually equipped (already-equipped blobs are free, not double-charged).
## Silently does nothing if the player can't afford equipping all of them.
## Shared by UnitInfoPanel's Equip Weapon/Equip Bucket buttons.
func _order_equip(item: String) -> void:
	var needing: Array = selected_blobs.filter(func(b): return b.equipped_item != item)
	if needing.is_empty():
		return
	var cost: int = EQUIP_COST * needing.size()
	if not GameManager.try_spend_wood(cost):
		return
	for blob in needing:
		blob.try_equip(item)

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
## opens the generic building info modal if a building was clicked, opens
## the resource info modal if a resource node was clicked, or clears the
## selection if empty ground was clicked (unless shift/additive is held, in
## which case an empty click does nothing).
func _handle_click_select(pos: Vector2, additive: bool) -> void:
	var hit := _raycast(pos, MASK_BLOBS)
	if hit and hit.collider.is_in_group("blobs"):
		if not additive:
			_clear_selection()
		_select_blob(hit.collider)
		_selection_changed()
		return

	var resource_hit := _raycast(pos, MASK_RESOURCES)
	if resource_hit:
		var building_owner := _find_building_owner(resource_hit.collider)
		if building_owner:
			building_menu.open_menu(building_owner)
			return
		if resource_hit.collider.is_in_group("resource_nodes"):
			resource_info_panel.open_for(resource_hit.collider)
			return

	if not additive:
		_clear_selection()
	_selection_changed()

## A clicked collider might *be* the building itself (StorageDepot/Wall,
## which attach their script directly to a root StaticBody3D) or might be
## a nested collision body whose *parent* is the building (Building.tscn's
## "Solid" child, or BeltSegment's ClickArea) -- checks both, returning null
## if neither applies. Also matches "structures" (extractor/processor/belt),
## which open the same generic BuildingMenu even though they aren't part of
## the separate "buildings" group Blob._find_nearest_building searches for a
## deposit target -- a belt out in the field must never be mistaken for one.
func _find_building_owner(collider: Node) -> Node:
	if collider.is_in_group("buildings") or collider.is_in_group("structures"):
		return collider
	var parent := collider.get_parent()
	if parent and (parent.is_in_group("buildings") or parent.is_in_group("structures")):
		return parent
	return null

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
	_selection_changed()

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
	var prior_count := selected_blobs.size()
	selected_blobs = selected_blobs.filter(is_instance_valid)
	if selected_blobs.size() != prior_count:
		_selection_changed()
	if selected_blobs.is_empty():
		return
	var hit := _raycast(pos, MASK_RESOURCES | MASK_GROUND)
	if not hit:
		return
	if _pending_patrol:
		_pending_patrol = false
		var patrol_tolerance := _group_move_tolerance()
		for blob in selected_blobs:
			blob.command_patrol(hit.position, patrol_tolerance)
		Effects.spawn_command_marker(self, hit.position + Vector3(0.0, 0.05, 0.0), COLOR_PATROL)
		return
	var building_owner := _find_building_owner(hit.collider)
	var is_under_construction: bool = building_owner != null and "is_under_construction" in building_owner and building_owner.is_under_construction
	if is_under_construction:
		_issue_build_orders(building_owner)
		Effects.spawn_command_marker(self, building_owner.global_position + Vector3(0.0, 0.05, 0.0), COLOR_HARVEST)
	elif hit.collider.is_in_group("resource_nodes"):
		_issue_harvest_orders(hit.collider)
		Effects.spawn_command_marker(self, hit.collider.global_position + Vector3(0.0, 0.05, 0.0), COLOR_HARVEST)
	else:
		var move_tolerance := _group_move_tolerance()
		for blob in selected_blobs:
			blob.command_move(hit.position, move_tolerance)
		Effects.spawn_command_marker(self, hit.position + Vector3(0.0, 0.05, 0.0), COLOR_MOVE)

## How much slack (see Blob.move_tolerance) a shared move/patrol point should
## give every blob in the current selection: solo orders get none (exact
## point, unchanged behavior), and it grows with the group size, capped, so
## a big squad doesn't leave every blob but one stuck circling the one spot
## someone else already reached.
const MOVE_TOLERANCE_PER_EXTRA_BLOB := 0.3
const MAX_MOVE_TOLERANCE := 2.5
func _group_move_tolerance() -> float:
	return min(MAX_MOVE_TOLERANCE, max(0, selected_blobs.size() - 1) * MOVE_TOLERANCE_PER_EXTRA_BLOB)

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

	# Animals (food) and water sources need the matching tool equipped
	# (see Blob.equipped_item) -- everything else is unrestricted. A blob
	# missing the right tool is left alone rather than silently ignored, so
	# the player understands why nothing happened.
	var required_item: String = ITEM_REQUIRED_FOR_RESOURCE.get(target_type, "")

	var assigned_count: Dictionary = {}
	for blob in selected_blobs:
		if required_item != "" and blob.equipped_item != required_item:
			Effects.spawn_floating_text(self, blob.global_position + Vector3(0.0, 1.6, 0.0), "Needs a %s!" % required_item.capitalize(), Color(1.0, 0.35, 0.3))
			continue
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

## Sends every currently-selected blob to help construct `building` (an
## under-construction Town Hall/Storage Depot), each with its own evenly-
## spaced approach angle around it -- the same "don't all aim for the same
## spot" trick _issue_harvest_orders uses for resource nodes -- so a squad
## sent to build doesn't jam each other trying to stand in the same place.
func _issue_build_orders(building: Node) -> void:
	for i in selected_blobs.size():
		var angle := (TAU / selected_blobs.size()) * i
		selected_blobs[i].command_build(building, angle)

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

## Called after anything that adds/removes/prunes the selection: updates
## the HUD's count and shows/hides the unit-info panel to match. A single
## selected blob gets the detailed stats/inventory view; multiple get a
## compact per-kind grouped overview instead of hiding the panel entirely.
func _selection_changed() -> void:
	hud.set_selected_count(selected_blobs.size())
	if selected_blobs.is_empty():
		unit_info_panel.hide_panel()
	elif selected_blobs.size() == 1 and is_instance_valid(selected_blobs[0]):
		unit_info_panel.show_blob(selected_blobs[0])
	else:
		unit_info_panel.show_group(selected_blobs)


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
		if _build_selected_kind == "extractor":
			_show_extractor_range_indicators()
	else:
		_clear_ghost()
		_clear_extractor_range_indicators()

## Signal handler for BuildPalette.kind_selected: switches which structure
## the next placement will be.
func _on_build_kind_selected(kind_id: String) -> void:
	_build_selected_kind = kind_id
	build_palette.set_selected_kind(kind_id)
	_update_ghost_validity()
	if kind_id == "extractor":
		_show_extractor_range_indicators()
	else:
		_clear_extractor_range_indicators()

## Spawns a translucent green disc over every resource node, sized to
## EXTRACTOR_LINK_RADIUS, so the player can see at a glance where an
## extractor can legally be linked instead of trial-and-error placement.
func _show_extractor_range_indicators() -> void:
	_clear_extractor_range_indicators()
	for n in get_tree().get_nodes_in_group("resource_nodes"):
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
		add_child(indicator)
		indicator.global_position = n.global_position + Vector3(0.0, 0.03, 0.0)
		_extractor_range_indicators.append(indicator)

## Removes every extractor-range indicator, e.g. when switching to a
## different build kind or leaving build mode entirely.
func _clear_extractor_range_indicators() -> void:
	for indicator in _extractor_range_indicators:
		if is_instance_valid(indicator):
			indicator.queue_free()
	_extractor_range_indicators.clear()

## Routes all input while build mode is active: mouse movement re-positions
## the ghost, left click places whatever's selected in the palette, right
## click demolishes whatever structure is under the ghost cell (regardless
## of which kind is currently selected for placement), 'R' rotates the
## ghost 90 degrees, and Escape exits build mode entirely.
func _handle_build_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_ghost_position(event.position)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_place_structure()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_demolish_at(_build_ghost_cell)
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

## Whether `cell` is a valid target for the currently-selected build kind.
## Every kind (building or factory piece) occupies exactly its own single
## cell -- a building's input/output ports are directions to its
## *neighboring* cells (where a belt goes), not extra cells the building
## itself claims, same as how an Extractor/Processor's single output side
## works with a belt sitting next to it, not inside it. A building kind
## must also be unlocked; an extractor must be within linking range of an
## actual resource node. (Demolishing is a right-click, handled separately
## in _handle_build_input -- it isn't a selectable placement kind.)
func _is_placement_valid(cell: Vector2i) -> bool:
	var building_kind = BuildingKinds.get_kind(_build_selected_kind)
	if building_kind and not GameManager.is_building_unlocked(_build_selected_kind):
		return false

	if get_structure_at(cell) != null:
		return false
	if _build_selected_kind == "extractor":
		return _find_resource_node_near(grid_to_world(cell)) != null
	return true

## Every grid cell `kind_id` occupies if placed with its anchor at `anchor`
## -- always just the anchor itself; a building's ports describe directions
## to its neighboring cells, not additional cells it claims (see
## _is_placement_valid). Kept as its own helper (rather than inlining
## `[anchor]`) so demolish/placement code reads the same way regardless of
## kind, and so a genuinely multi-cell building could extend this later.
func _get_footprint_cells(_kind_id: String, anchor: Vector2i) -> Array:
	return [anchor]

## Wood cost of placing `kind_id`, whether it's a building kind (cost lives
## on its BuildingKinds entry) or a factory piece (cost lives in BUILD_COSTS).
func _get_build_cost(kind_id: String) -> int:
	var building_kind = BuildingKinds.get_kind(kind_id)
	if building_kind:
		return building_kind.build_cost
	return BUILD_COSTS.get(kind_id, 0)

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

## Attempts to place the currently-selected build kind at the ghost's cell:
## validates placement, spends the wood cost, instantiates and orients the
## real structure, and registers it on the grid. Silently does nothing if
## the action is invalid or unaffordable -- the ghost's color already told
## the player which case they're in. (Demolishing is a separate right-click
## action, see _demolish_at.)
func _try_place_structure() -> void:
	if not _is_placement_valid(_build_ghost_cell):
		return
	var cost := _get_build_cost(_build_selected_kind)
	if not GameManager.try_spend_wood(cost):
		return

	var node: Node3D = _instantiate_structure(_build_selected_kind)
	# Buildings don't rotate to face a placement direction (their ports are
	# fixed world-relative offsets, see BuildingKinds) -- only factory
	# pieces expose a `facing` property, so this is skipped for them.
	if "facing" in node:
		node.facing = _build_facing
	if "kind_id" in node:
		node.kind_id = _build_selected_kind
	add_child(node)
	node.global_position = grid_to_world(_build_ghost_cell)
	if "facing" in node:
		node.look_at(node.global_position + Vector3(_build_facing.x, 0.0, _build_facing.y), Vector3.UP)

	var footprint := _get_footprint_cells(_build_selected_kind, _build_ghost_cell)
	for cell in footprint:
		register_structure(cell, node)
		if _kind_blocks_movement(_build_selected_kind):
			_mark_pathing_cell(cell, true)
	node.set_meta("build_kind", _build_selected_kind)
	node.set_meta("occupied_cells", footprint)

	if _build_selected_kind == "extractor":
		node.linked_node = _find_resource_node_near(node.global_position)

	_refresh_neighbor_visuals(_build_ghost_cell)
	_update_ghost_validity()

## Removes whatever structure occupies `cell` (a right-click in build mode,
## regardless of which kind is currently selected for placement), refunding
## half its original wood cost, freeing any item it was holding (a belt's
## current_item) rather than leaving it orphaned on the grid, clearing
## every grid cell it occupied (not just `cell` itself -- a building spans
## multiple cells, see _get_footprint_cells) and re-opening any pathing
## cells it had closed off. No-ops if `cell` is empty.
func _demolish_at(cell: Vector2i) -> void:
	var structure := get_structure_at(cell)
	if structure == null:
		return
	if "current_item" in structure and structure.current_item:
		structure.current_item.queue_free()
	var occupied: Array = structure.get_meta("occupied_cells", [cell])
	var kind: String = structure.get_meta("build_kind", "belt")
	for occupied_cell in occupied:
		_grid_structures.erase(occupied_cell)
		if _kind_blocks_movement(kind):
			_mark_pathing_cell(occupied_cell, false)
	var refund: int = _get_build_cost(kind) / 2
	if refund > 0:
		GameManager.add_resource("wood", refund)
	structure.queue_free()
	_refresh_neighbor_visuals(cell)
	_update_ghost_validity()

## Asks the structure at `cell` and every structure in the 4 cells around it
## (belts only actually respond -- see BeltSegment.refresh_connections) to
## re-check their neighbors and update which of their side walls are open,
## so a belt chain visually reacts immediately when a new piece is placed
## next to it or an existing one is removed, without needing a full-grid
## rescan. `cell` itself needs this too, not just its neighbors -- a belt's
## _ready() can't do its own initial check (see BeltSegment._ready), since
## World sets its real position/rotation only *after* add_child().
func _refresh_neighbor_visuals(cell: Vector2i) -> void:
	var offsets := [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for offset in offsets:
		var neighbor := get_structure_at(cell + offset)
		if neighbor and neighbor.has_method("refresh_connections"):
			neighbor.refresh_connections()

## Instantiates (but does not yet place) the scene for `kind` -- a building
## kind's scene comes from its BuildingKinds entry, a factory piece's from
## World's own preloaded scenes.
func _instantiate_structure(kind: String) -> Node3D:
	var building_kind = BuildingKinds.get_kind(kind)
	if building_kind:
		return building_kind.scene.instantiate()
	match kind:
		"extractor":
			return EXTRACTOR_SCENE.instantiate()
		"processor":
			return PROCESSOR_SCENE.instantiate()
		"wall":
			return WALL_SCENE.instantiate()
		_:
			return BELT_SCENE.instantiate()

## Removes the ghost preview, e.g. when exiting build mode.
func _clear_ghost() -> void:
	if _build_ghost:
		_build_ghost.queue_free()
		_build_ghost = null
		_build_ghost_material = null
