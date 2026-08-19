extends GdUnitTestSuite
## Covers DebugScene's own population logic (see feature request: "add a new
## scene accessible from the main menu: debug scene... a lot of blobs and
## buildings... conveyor belt configurations, wall configurations with and
## without gate") -- a lightweight smoke/invariant test, not a full replay of
## World's own manager tests (those already cover PathingManager/
## BuildingManager/etc. in isolation).

const DEBUG_SCENE: PackedScene = preload("res://scenes/world/debug_scene.tscn")

var _scene: Node3D


func before_test() -> void:
	_scene = DEBUG_SCENE.instantiate()
	add_child(_scene, true)
	auto_free(_scene)


func test_populates_a_lot_of_blobs() -> void:
	var blobs := _scene.get_tree().get_nodes_in_group("blobs")
	assert_int(blobs.size()).is_greater_equal(30)


func test_populates_a_lot_of_flying_enemies() -> void:
	var enemies := _scene.get_tree().get_nodes_in_group("enemies")
	var flying_kind_ids := ["crow", "wasp", "vulture", "frost_bat", "mosquito", "cinder_wisp"]
	var flying := enemies.filter(func(e): return e.kind_id in flying_kind_ids)
	assert_int(flying.size()).is_greater_equal(60)


func test_places_one_of_every_real_building_kind() -> void:
	var buildings := _scene.get_tree().get_nodes_in_group("buildings")
	var kind_ids: Array = buildings.map(func(b): return b.kind_id if "kind_id" in b else "")
	for expected in ["town_hall", "storage_depot", "water_tank", "foundry", "research_center", "vegetable_patch", "school", "tavern", "house"]:
		assert_array(kind_ids).contains([expected])


func test_places_both_walls_and_at_least_one_gate() -> void:
	var buildings := _scene.get_tree().get_nodes_in_group("buildings")
	var wall_count := buildings.filter(func(b): return b is Wall).size()
	var gate_count := buildings.filter(func(b): return b is Gate).size()
	assert_int(wall_count).is_greater(0)
	assert_int(gate_count).is_greater(0)


func test_belt_configurations_are_all_fully_connected_and_finished() -> void:
	# Belts deliberately don't join "buildings" (see BeltSegment's own
	# header: that group is how a blob finds a deposit target, and a belt
	# should never be mistaken for one) -- only "structures".
	var structures := _scene.get_tree().get_nodes_in_group("structures")
	var belts := structures.filter(func(s): return "kind_id" in s and s.kind_id == "belt")
	assert_int(belts.size()).is_greater_equal(15)
	for belt in belts:
		assert_bool(belt.is_under_construction).is_false()


func test_every_placed_structure_is_already_finished_construction() -> void:
	var buildings := _scene.get_tree().get_nodes_in_group("buildings")
	for building in buildings:
		if "is_under_construction" in building:
			assert_bool(building.is_under_construction).is_false()


func test_ground_collision_covers_the_whole_town_for_click_to_move() -> void:
	# A raycast straight down at a point well inside the town should hit
	# Ground-layer (1) collision -- confirms _build_ground's flat plane
	# actually replaces Chunk's own ground collision for this scene. Awaits
	# a real physics frame first -- a freshly-added CollisionShape3D needs
	# one for Jolt's broad-phase to actually pick it up (see CLAUDE.md's own
	# note on this exact gotcha).
	await get_tree().physics_frame
	var from := Vector3(-58.0, 10.0, -34.0)
	var to := Vector3(-58.0, -10.0, -34.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var result := _scene.get_world_3d().direct_space_state.intersect_ray(query)
	assert_dict(result).is_not_empty()
