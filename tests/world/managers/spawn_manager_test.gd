extends GdUnitTestSuite
## Covers SpawnManager.spawn_enemies_near_base -- the debug "Spawn Enemies
## Near Base" button's underlying behavior: spawns exactly the requested
## count, in a ring around the map origin when no Town Hall exists yet.

func _make_spawn_manager(world: Node3D) -> SpawnManager:
	var spawn_manager := SpawnManager.new()
	spawn_manager.setup(world, ChunkManager.new())
	return spawn_manager


func test_spawns_exactly_the_requested_count() -> void:
	var world := Node3D.new()
	add_child(world, true)
	auto_free(world)
	var spawn_manager := _make_spawn_manager(world)

	var before: Array = world.get_tree().get_nodes_in_group("enemies")
	spawn_manager.spawn_enemies_near_base(5)
	var after: Array = world.get_tree().get_nodes_in_group("enemies")
	var spawned := after.filter(func(n): return not before.has(n))

	assert_int(spawned.size()).is_equal(5)


func test_spawns_within_radius_of_the_map_origin_when_no_town_hall_exists() -> void:
	var world := Node3D.new()
	add_child(world, true)
	auto_free(world)
	var spawn_manager := _make_spawn_manager(world)

	var before: Array = world.get_tree().get_nodes_in_group("enemies")
	spawn_manager.spawn_enemies_near_base(3)
	var after: Array = world.get_tree().get_nodes_in_group("enemies")
	var spawned := after.filter(func(n): return not before.has(n))

	for enemy in spawned:
		assert_float(enemy.global_position.distance_to(Vector3.ZERO)).is_less_equal(SpawnManager.DEBUG_BASE_SPAWN_RADIUS + 0.5)
