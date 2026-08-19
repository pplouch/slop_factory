extends Node3D
## Debug/testing scene (see feature request: "add a new scene accessible
## from the main menu: debug scene... add a lot of blobs and buildings...
## conveyor belt configurations, wall configurations with and without gate,
## so it will be easier to debug and test new meshes") -- a flat, single
## ground plane (no Chunk streaming, no biomes, no fog-of-war) with a large
## pre-built "factory town" showcasing every building kind, several
## conveyor-belt layouts (straight run, corner turn, two-way merge), wall
## layouts with and without a Gate, and a big flock of flying enemies (see
## feature request: "add a lot of flying enemies in the debug scene") on top
## of the usual scattered blob crowd, all already fully constructed so
## nothing needs to wait on blob labor. Reuses the exact same manager split
## World itself does (see world.gd's own header) for Build Mode/selection/
## orders/the debug menu to stay fully interactive here too -- placing a new
## building, selecting/ordering blobs, and toggling debug overlays all work
## exactly as they do in the real game, just without ChunkManager/
## SpawnManager's ambient population.

const MAIN_MENU_SCENE_PATH := "res://scenes/ui/main_menu.tscn"
const MINIMAP_HALF_SIZE := 90.0
const FOG_HALF_SIZE := 2000.0
const GROUND_HALF_SIZE := 90.0

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
@onready var chest_panel = $ChestPanel
@onready var village_panel = $VillagePanel
@onready var slot_machine_panel = $SlotMachinePanel
@onready var _sun: DirectionalLight3D = $DirectionalLight3D

var _pathing_manager := PathingManager.new()
var _building_manager := BuildingManager.new()
var _selection_manager := SelectionManager.new()
var _order_manager := OrderManager.new()
var _debug_overlay_manager := DebugOverlayManager.new()
var _fog_manager := FogManager.new()
var _day_night_manager := DayNightManager.new()

const BLOB_SCENE: PackedScene = preload("res://scenes/units/blob/blob.tscn")
## Cycled through when scattering blobs -- every kind gets some
## representation regardless of its real tech-tree unlock state (this scene
## never checks GameManager.unlocked_blob_kinds, it just wants variety on
## screen).
const BLOB_KIND_CYCLE := ["worker", "worker", "scout", "hauler", "brute", "builder", "hero", "mage"]
const BLOB_SCATTER_COUNT := 30
const BLOB_SCATTER_HALF_SIZE := 70.0

const ENEMY_SCENE: PackedScene = preload("res://scenes/units/enemy/enemy.tscn")
## Every "flying" EnemyKinds kind (see Biomes -- normally one flying kind
## spawns per biome; this scene has no biomes, so it just cycles all of them
## for variety), scattered in a big flock rather than the ambient handful
## SpawnManager ever keeps alive in a real game, since this scene's whole
## point is "see a lot of the thing on screen at once" (see feature request:
## "add a lot of flying enemies in the debug scene").
const FLYING_ENEMY_KIND_CYCLE := ["crow", "wasp", "vulture", "frost_bat", "mosquito", "cinder_wisp"]
const FLYING_ENEMY_SCATTER_COUNT := 60
const FLYING_ENEMY_SCATTER_HALF_SIZE := 70.0


func _ready() -> void:
	_configure_environment($WorldEnvironment.environment)

	minimap.set_world_bounds(MINIMAP_HALF_SIZE)
	minimap.set_camera(camera_rig, camera)

	_pathing_manager.setup()
	_building_manager.setup(self, _pathing_manager, _fog_manager)
	_selection_manager.setup(self)
	_order_manager.setup(self, _selection_manager)
	_debug_overlay_manager.setup(self)
	_fog_manager.setup(self, FOG_HALF_SIZE)
	minimap.set_fog_source(_fog_manager.fog_texture, _fog_manager.world_half_size)
	_day_night_manager.setup(self, _sun, $WorldEnvironment.environment.sky.sky_material)
	# No fog-of-war in a scene whose whole point is "see every building the
	# instant it loads" -- also lets Build Mode place anything anywhere here
	# (see feature backlog 2: fog-of-war placement gating), matching "all
	# the buildings should be visible on the map as the scene loads".
	_fog_manager.reveal_all()

	_build_ground()
	_populate_factory_town()
	# CameraRig otherwise starts at the world origin, which is empty ground
	# in this scene (the town is laid out to one side -- see
	# _place_buildings/_place_belt_configurations/_place_wall_configurations'
	# own origins) -- centered on the building cluster instead so the town
	# is actually what greets the player the instant this scene loads (see
	# feature request: "all the buildings should be visible on the map as
	# the scene loads").
	camera_rig.global_position = Vector3(-58.0, 0.0, -34.0)

	build_palette.toggle_requested.connect(_building_manager.toggle_build_mode)
	build_palette.kind_selected.connect(_building_manager.on_build_kind_selected)

	debug_menu.toggle_requested.connect(_debug_overlay_manager.toggle_debug_menu)
	debug_menu.spawn_blob_requested.connect(_debug_overlay_manager.debug_spawn_blob)
	debug_menu.add_resources_requested.connect(_debug_overlay_manager.debug_add_resources)
	debug_menu.clear_fog_requested.connect(_fog_manager.reveal_all)
	debug_menu.set_time_requested.connect(_day_night_manager.set_time_fraction)
	debug_menu.toggle_hitboxes_requested.connect(_debug_overlay_manager.toggle_debug_visuals)
	debug_menu.toggle_grid_requested.connect(_debug_overlay_manager.toggle_world_grid)

	unit_info_panel.patrol_requested.connect(_order_manager.order_pending_patrol)
	unit_info_panel.hold_requested.connect(_order_manager.order_hold)
	unit_info_panel.explore_requested.connect(_order_manager.order_explore)
	unit_info_panel.equip_weapon_requested.connect(func(): _order_manager.order_equip("weapon"))
	unit_info_panel.equip_bucket_requested.connect(func(): _order_manager.order_equip("bucket"))

	minimap.camera_move_requested.connect(_move_camera_to)
	tech_tree_panel.opened.connect(func(): close_other_ui(tech_tree_panel))
	hud.end_run_requested.connect(func(): get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH))

## Same tuning World._configure_environment uses -- see that function's own
## header for why (flat low-poly albedo colors washed out under a punchier
## tonemap during testing).
func _configure_environment(env: Environment) -> void:
	env.ambient_light_energy = 0.85
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.8
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.2

## One big flat plane instead of Chunk's streamed, height-jittered, biome-
## textured tiles (see feature request: "no need to create chunks, only a
## flat surface with buildings on it") -- a plain plains-green
## StandardMaterial3D rather than Chunk's whole procedural-texture/normal-
## map pipeline, since this scene's whole point is buildings/blobs/meshes,
## not terrain. Collision stays on the same "Ground" layer (1) every
## click-to-move/build-mode raycast already expects, matching Chunk's own
## convention.
func _build_ground() -> void:
	var mesh_inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_HALF_SIZE * 2.0, GROUND_HALF_SIZE * 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Biomes.get_biome("plains").ground_color
	mat.roughness = 0.95
	plane.material = mat
	mesh_inst.mesh = plane
	add_child(mesh_inst)

	var body := StaticBody3D.new()
	body.collision_layer = 1  # Ground
	body.collision_mask = 0
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(GROUND_HALF_SIZE * 2.0, 1.0, GROUND_HALF_SIZE * 2.0)
	collision.shape = shape
	collision.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(collision)

## Builds the whole pre-populated town: one of every real building kind
## (see _place_buildings), several belt-line configurations (see
## _place_belt_configurations), wall runs with and without a Gate (see
## _place_wall_configurations), a scattered crowd of blobs across several
## different kinds (see _scatter_blobs), and a big flock of flying enemies
## (see _scatter_flying_enemies).
func _populate_factory_town() -> void:
	_place_buildings()
	_place_belt_configurations()
	_place_wall_configurations()
	_scatter_blobs()
	_scatter_flying_enemies()

## Instantiates, places, registers, and immediately finishes construction on
## `kind_id` at `cell` -- the same sequence BuildingManager.try_place_structure
## itself uses (instantiate -> set facing/kind_id -> add_child -> position ->
## register_structure/mark_cell -> refresh_neighbor_visuals), minus the cost-
## spending and auto-assign-builders steps (nothing here should cost
## resources or need blob labor -- see feature request: "all the buildings
## should be visible on the map as the scene loads").
func _place_structure(kind_id: String, cell: Vector2i, facing: Vector2i = Vector2i(0, 1)) -> Node3D:
	var node: Node3D = _building_manager.instantiate_structure(kind_id)
	if "facing" in node:
		node.facing = facing
	if "kind_id" in node:
		node.kind_id = kind_id
	add_child(node)
	node.global_position = BuildingManager.grid_to_world(cell)
	if "facing" in node:
		node.look_at(node.global_position + Vector3(facing.x, 0.0, facing.y), Vector3.UP)

	_building_manager.register_structure(cell, node)
	if _pathing_manager.structure_blocks_movement(node):
		_pathing_manager.mark_cell(cell, true)
	node.set_meta("build_kind", kind_id)
	node.set_meta("occupied_cells", [cell])

	if "is_under_construction" in node:
		node.is_under_construction = false
		node._apply_construction_visual(1.0)

	_building_manager.refresh_neighbor_visuals(cell)
	return node

## One of every real BuildingKinds entry (excluding Wall/Gate/Belt/Road/Pipe,
## the factory-grid pieces placed separately below) in a 3x3 grid, plus a
## couple of extra Houses nearby for a bit of "residential district" scale.
func _place_buildings() -> void:
	const KIND_GRID := [
		"town_hall", "storage_depot", "water_tank",
		"foundry", "research_center", "vegetable_patch",
		"school", "tavern", "house",
	]
	const ORIGIN := Vector2i(-34, -22)
	const SPACING := 5
	for i in KIND_GRID.size():
		var row := i / 3
		var col := i % 3
		_place_structure(KIND_GRID[i], ORIGIN + Vector2i(col * SPACING, row * SPACING))
	_place_structure("house", ORIGIN + Vector2i(-SPACING, 0))
	_place_structure("house", ORIGIN + Vector2i(-SPACING, SPACING))

## Three distinct conveyor layouts (see feature request: "add a lot of
## different conveyor belt configurations") -- a straight run, a corner
## turn, and a two-belt merge into one shared output (exercising
## LinkableBuilding._resolve_fair_input, see that function's own header).
func _place_belt_configurations() -> void:
	const ORIGIN := Vector2i(6, -22)

	# Straight run, 5 segments, all facing east.
	for i in 5:
		_place_structure("belt", ORIGIN + Vector2i(i, 0), Vector2i(1, 0))

	# Corner turn: east for 3 cells, then turns south for 3 more.
	var turn_row := ORIGIN + Vector2i(0, 3)
	for i in 3:
		_place_structure("belt", turn_row + Vector2i(i, 0), Vector2i(1, 0))
	for i in 3:
		_place_structure("belt", turn_row + Vector2i(2, i + 1), Vector2i(0, 1))

	# Merge: two 2-segment approaches (from the west and from the north)
	# feeding the same cell, which then continues east one more segment.
	var merge_cell := ORIGIN + Vector2i(9, 7)
	_place_structure("belt", merge_cell + Vector2i(-2, 0), Vector2i(1, 0))
	_place_structure("belt", merge_cell + Vector2i(-1, 0), Vector2i(1, 0))
	_place_structure("belt", merge_cell + Vector2i(0, -2), Vector2i(0, 1))
	_place_structure("belt", merge_cell + Vector2i(0, -1), Vector2i(0, 1))
	_place_structure("belt", merge_cell, Vector2i(1, 0))
	_place_structure("belt", merge_cell + Vector2i(1, 0), Vector2i(1, 0))

## Three wall layouts (see feature request: "wall configurations with and
## without a gate") -- a plain run, a run with a Gate in the middle, and a
## small enclosed pen whose only entrance is a Gate (also a convenient live
## test case for the "unit surrounded by unbuilt/built walls" pathing fix --
## see PathingManager.is_reachable/Blob._reachable_approach_point).
func _place_wall_configurations() -> void:
	const PLAIN_ORIGIN := Vector2i(-34, 4)
	for i in 5:
		_place_structure("wall", PLAIN_ORIGIN + Vector2i(i, 0))

	const GATED_ORIGIN := Vector2i(-34, 8)
	for i in 5:
		var cell := GATED_ORIGIN + Vector2i(i, 0)
		if i == 2:
			_place_structure("gate", cell)
		else:
			_place_structure("wall", cell)

	const PEN_CENTER := Vector2i(-30, 13)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if maxi(absi(dx), absi(dz)) != 1:
				continue
			var cell := PEN_CENTER + Vector2i(dx, dz)
			if dx == 0 and dz == 1:
				_place_structure("gate", cell)
			else:
				_place_structure("wall", cell)
	# A couple of blobs already inside the pen -- immediately exercises the
	# "enclosed by walls" reachable-approach-point fix if one of them is
	# given a build/harvest order from in here.
	_spawn_blob("worker", BuildingManager.grid_to_world(PEN_CENTER) + Vector3(0.3, 0.0, 0.3))
	_spawn_blob("worker", BuildingManager.grid_to_world(PEN_CENTER) + Vector3(-0.3, 0.0, -0.3))

## Scatters BLOB_SCATTER_COUNT blobs, cycling through BLOB_KIND_CYCLE for
## variety, across a big area centered on the town (random positions --
## exact overlap with a building/belt/wall is harmless, a blob's own
## physics/stall-detection settles it clear on the next physics frame the
## same way an ordinary crowded order would).
func _scatter_blobs() -> void:
	for i in BLOB_SCATTER_COUNT:
		var kind_id: String = BLOB_KIND_CYCLE[i % BLOB_KIND_CYCLE.size()]
		var pos := Vector3(
			randf_range(-BLOB_SCATTER_HALF_SIZE, BLOB_SCATTER_HALF_SIZE), 0.0,
			randf_range(-BLOB_SCATTER_HALF_SIZE, BLOB_SCATTER_HALF_SIZE)
		)
		_spawn_blob(kind_id, pos)

func _spawn_blob(kind_id: String, pos: Vector3) -> void:
	var blob: Node3D = BLOB_SCENE.instantiate()
	blob.kind_id = kind_id
	add_child(blob)
	blob.global_position = pos
	blob.play_spawn_pop()

## Scatters FLYING_ENEMY_SCATTER_COUNT enemies, cycling through every
## "flying" EnemyKinds kind, across the same area _scatter_blobs covers --
## Enemy's own _physics_process lifts each one to FLIGHT_ALTITUDE on its
## first tick regardless of the y given here (see Enemy._physics_process),
## so the initial position only needs to be right on x/z.
func _scatter_flying_enemies() -> void:
	for i in FLYING_ENEMY_SCATTER_COUNT:
		var kind_id: String = FLYING_ENEMY_KIND_CYCLE[i % FLYING_ENEMY_KIND_CYCLE.size()]
		var pos := Vector3(
			randf_range(-FLYING_ENEMY_SCATTER_HALF_SIZE, FLYING_ENEMY_SCATTER_HALF_SIZE), 0.0,
			randf_range(-FLYING_ENEMY_SCATTER_HALF_SIZE, FLYING_ENEMY_SCATTER_HALF_SIZE)
		)
		var enemy: Node3D = ENEMY_SCENE.instantiate()
		enemy.kind_id = kind_id
		add_child(enemy)
		enemy.global_position = pos

## Same as World.close_other_ui -- see that function's own header.
func close_other_ui(opened: Node) -> void:
	if building_menu != opened:
		building_menu.close_menu()
	if resource_info_panel != opened:
		resource_info_panel.close_panel()
	if enemy_info_panel != opened:
		enemy_info_panel.close_panel()
	if chest_panel != opened:
		chest_panel.close_panel()
	if village_panel != opened:
		village_panel.close_panel()
	if slot_machine_panel != opened:
		slot_machine_panel.close_panel()
	if tech_tree_panel != opened:
		tech_tree_panel.close_panel()
	if debug_menu != opened:
		_debug_overlay_manager.close_debug_menu()
	if unit_info_panel != opened:
		_selection_manager.clear_selection()
		_selection_manager.selection_changed()

func _move_camera_to(world_pos: Vector3) -> void:
	camera_rig.position.x = world_pos.x
	camera_rig.position.z = world_pos.z

func _process(delta: float) -> void:
	_fog_manager.process()
	_day_night_manager.process(delta)
	hud.set_day_info(_day_night_manager.current_day(), _day_night_manager.is_night())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		_building_manager.toggle_build_mode()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and building_menu.visible:
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

func raycast(screen_pos: Vector2, mask: int) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = mask
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)


# ==============================================================================
# PUBLIC FACADE -- see World's own header. Kept identical so every
# BuildableStructure/Wall/Gate/BeltSegment/Extractor/Processor placed in this
# scene reaches the exact same duck-typed methods they'd find on the real
# World.
# ==============================================================================

func compute_path(from: Vector3, to: Vector3) -> Array:
	return _pathing_manager.compute_path(from, to)

func is_reachable(from: Vector3, to: Vector3) -> bool:
	return _pathing_manager.is_reachable(from, to)

func grid_to_world(cell: Vector2i) -> Vector3:
	return BuildingManager.grid_to_world(cell)

func world_to_grid(pos: Vector3) -> Vector2i:
	return BuildingManager.world_to_grid(pos)

func get_structure_at(cell: Vector2i) -> Node:
	return _building_manager.get_structure_at(cell)

func register_structure(cell: Vector2i, node: Node) -> void:
	_building_manager.register_structure(cell, node)
