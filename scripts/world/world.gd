extends Node3D
## Top-level game controller. Owns the @onready node references every
## manager below needs (camera, UI panels) and the top-level Godot lifecycle
## hooks (_ready/_process/_unhandled_input), but delegates the actual logic
## to focused manager objects instantiated in _ready() -- see each manager's
## own header for what it owns:
##  - ChunkManager: Minecraft-style chunk streaming
##  - SpawnManager: founder blobs + ambient enemy population
##  - PathingManager: the A*-grid blobs/enemies route around
##  - BuildingManager: factory placement grid + Build Mode
##  - SelectionManager: mouse-driven unit selection/hover
##  - OrderManager: standing orders + right-click order issuing
##  - DebugOverlayManager: everything DebugMenu's buttons drive
##  - FogManager: sticky fog-of-war shared by Minimap and the 3D ground mask
##
## Managers are plain RefCounted objects, not scene-tree Nodes -- they hold a
## `_world` reference back to this node for whatever needs add_child/
## get_tree()/raycasting, and World's own _ready/_process/_unhandled_input
## call into them directly rather than each holding its own engine callbacks.
##
## World is not a singleton or autoload and has no class_name: Blob/
## BeltSegment/Wall/Extractor/Processor/every BuildableStructure reach it via
## `get_parent()` and call `compute_path`/`register_structure`/
## `get_structure_at`/`world_to_grid`/`grid_to_world` directly (duck-typed,
## no compile-time contract) -- those five methods below are a thin
## forwarding facade into whichever manager now actually owns them, kept so
## every existing `get_parent().foo(...)` call site works unchanged.
##
## Effect creation (rings, particles, floating text) is delegated to the
## Effects autoload (Factory pattern, see scripts/autoload/effects.gd) rather than
## instantiated by hand here.

# Physics layers (see Project Settings > Layer Names > 3D Physics for labels).
const MASK_GROUND := 1
const MASK_BLOBS := 2
const MASK_RESOURCES := 4

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
@onready var enemy_info_panel = $EnemyInfoPanel
@onready var tech_tree_panel = $TechTreePanel

# Half-size used for the minimap's world<->local mapping -- deliberately
# small and independent of FOG_HALF_SIZE below (a minimap is meant to be a
# local overview; PathingManager.PATHING_GRID_HALF_SIZE shares this same
# 90-unit scale too, its own still-unfixed instance of the same "doesn't
# reach as far as the camera can pan" limitation).
const MINIMAP_HALF_SIZE := 90.0
# Half-size used for the 3D fog plane's coverage -- matches CameraRig.BOUNDS
# exactly (not referenced directly since camera_rig.gd has no class_name;
# kept in sync by hand, same as PATHING_GRID_HALF_SIZE's already-documented
# independent tuning) so fog coverage reaches exactly as far as the camera
# can ever pan -- the player can never reach an edge to see fog stop, which
# is effectively "extends infinitely" from where it actually matters (see
# feature backlog 3: fog previously used this same constant as
# MINIMAP_HALF_SIZE, 90, which read as "fog only covers a small area").
const FOG_HALF_SIZE := 2000.0

var _chunk_manager := ChunkManager.new()
var _pathing_manager := PathingManager.new()
var _building_manager := BuildingManager.new()
var _spawn_manager := SpawnManager.new()
var _selection_manager := SelectionManager.new()
var _order_manager := OrderManager.new()
var _debug_overlay_manager := DebugOverlayManager.new()
var _fog_manager := FogManager.new()


## Godot lifecycle hook: wires up every manager (in dependency order --
## BuildingManager needs PathingManager, SpawnManager needs ChunkManager,
## OrderManager needs SelectionManager), streams in the chunks around the
## origin (where founder blobs start and the player will likely build
## first), seeds the ambient enemy population and starts the timer that
## keeps topping it back up, and connects every UI panel's signals to
## whichever manager now owns that behavior. Every other object (blobs,
## buildings, UI) already exists as scene children.
func _ready() -> void:
	minimap.set_world_bounds(MINIMAP_HALF_SIZE)

	_chunk_manager.setup(self)
	_pathing_manager.setup()
	_building_manager.setup(self, _pathing_manager, _fog_manager)
	_spawn_manager.setup(self, _chunk_manager)
	_selection_manager.setup(self)
	_order_manager.setup(self, _selection_manager)
	_debug_overlay_manager.setup(self)
	_fog_manager.setup(self, FOG_HALF_SIZE)
	minimap.set_fog_source(_fog_manager.fog_texture, _fog_manager.world_half_size)

	_spawn_manager.spawn_founder_blobs()
	_chunk_manager.ensure_chunks_loaded(Vector3.ZERO)

	for i in SpawnManager.ENEMY_TARGET_COUNT:
		_spawn_manager.spawn_one_enemy()
	var population_timer := Timer.new()
	population_timer.wait_time = SpawnManager.ENEMY_POPULATION_CHECK_INTERVAL
	population_timer.timeout.connect(_spawn_manager.maintain_enemy_population)
	add_child(population_timer)
	population_timer.start()

	build_palette.toggle_requested.connect(_building_manager.toggle_build_mode)
	build_palette.kind_selected.connect(_building_manager.on_build_kind_selected)

	debug_menu.toggle_requested.connect(_debug_overlay_manager.toggle_debug_menu)
	debug_menu.spawn_blob_requested.connect(_debug_overlay_manager.debug_spawn_blob)
	debug_menu.spawn_enemy_requested.connect(_spawn_manager.spawn_one_enemy)
	debug_menu.add_resources_requested.connect(_debug_overlay_manager.debug_add_resources)
	debug_menu.toggle_hitboxes_requested.connect(_debug_overlay_manager.toggle_debug_visuals)
	debug_menu.toggle_grid_requested.connect(_debug_overlay_manager.toggle_world_grid)

	unit_info_panel.patrol_requested.connect(_order_manager.order_pending_patrol)
	unit_info_panel.hold_requested.connect(_order_manager.order_hold)
	unit_info_panel.explore_requested.connect(_order_manager.order_explore)
	unit_info_panel.equip_weapon_requested.connect(func(): _order_manager.order_equip("weapon"))
	unit_info_panel.equip_bucket_requested.connect(func(): _order_manager.order_equip("bucket"))

	minimap.camera_move_requested.connect(_move_camera_to)
	tech_tree_panel.opened.connect(func(): close_other_ui(tech_tree_panel))

## Closes every other primary UI popup/panel and deselects any currently
## selected blobs whenever one of them opens, so BuildingMenu/
## ResourceInfoPanel/EnemyInfoPanel/TechTreePanel/DebugMenu/UnitInfoPanel
## (via unit selection) never stack on top of each other -- `opened` is
## whichever one just opened (skipped so it isn't immediately closed again).
## Every close call here is already idempotent (a no-op if that panel wasn't
## open to begin with), so this can be called unconditionally from any "a box
## just opened" call site rather than each site tracking what else is open.
func close_other_ui(opened: Node) -> void:
	if building_menu != opened:
		building_menu.close_menu()
	if resource_info_panel != opened:
		resource_info_panel.close_panel()
	if enemy_info_panel != opened:
		enemy_info_panel.close_panel()
	if tech_tree_panel != opened:
		tech_tree_panel.close_panel()
	if debug_menu != opened:
		_debug_overlay_manager.close_debug_menu()
	if unit_info_panel != opened:
		_selection_manager.clear_selection()
		_selection_manager.selection_changed()

## Signal handler for Minimap.camera_move_requested: re-centers the camera
## rig on the clicked world point (only x/z -- the rig's own y is whatever
## height/zoom already has it at, untouched by this).
func _move_camera_to(world_pos: Vector3) -> void:
	camera_rig.position.x = world_pos.x
	camera_rig.position.z = world_pos.z

## Godot per-frame hook: delegates to ChunkManager, which internally only
## re-checks chunk coverage every CHUNK_CHECK_INTERVAL, not every frame; and
## to FogManager, which reveals fog around blobs every frame.
func _process(delta: float) -> void:
	_chunk_manager.process(delta, camera_rig.position)
	_fog_manager.process()

## Central input router: while build mode is active, every input goes to
## BuildingManager instead. Otherwise: left button drives selection (click
## vs. drag-box, with shift held meaning "add to selection"), right button
## issues an order to whatever's currently selected, and plain mouse motion
## (while not dragging) drives the hover highlight.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		_building_manager.toggle_build_mode()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and building_menu.visible:
		# A right-click anywhere -- not just on another building -- dismisses
		# the open "This Building" info modal instead of falling through to
		# a move/harvest order (or, in build mode, a demolish) behind it.
		building_menu.close_menu()
		return
	if _building_manager.is_build_mode_active():
		_building_manager.handle_build_input(event)
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_selection_manager.handle_left_button(event)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_order_manager.handle_right_click(event.position)
	elif event is InputEventMouseMotion:
		_selection_manager.handle_mouse_motion(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_order_manager.handle_order_key(event.keycode)

## Fires a physics ray from the camera through the given screen position and
## returns the first hit whose collision layer matches `mask` (empty
## Dictionary if nothing was hit). Public (no leading underscore) since
## SelectionManager/OrderManager/BuildingManager all call this on `_world`
## for their own click/hover/ghost-placement raycasts.
func raycast(screen_pos: Vector2, mask: int) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = mask
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)


# ============================================================================
# PUBLIC FACADE -- see this file's header. Blob/BeltSegment/Wall/Extractor/
# Processor/every BuildableStructure reach these via get_parent(), duck-typed
# with no compile-time contract, so these five signatures must stay exactly
# as they were before the manager split.
# ============================================================================

func compute_path(from: Vector3, to: Vector3) -> Array:
	return _pathing_manager.compute_path(from, to)

func grid_to_world(cell: Vector2i) -> Vector3:
	return BuildingManager.grid_to_world(cell)

func world_to_grid(pos: Vector3) -> Vector2i:
	return BuildingManager.world_to_grid(pos)

func get_structure_at(cell: Vector2i) -> Node:
	return _building_manager.get_structure_at(cell)

func register_structure(cell: Vector2i, node: Node) -> void:
	_building_manager.register_structure(cell, node)
