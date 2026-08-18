extends GdUnitTestSuite
## Covers ChunkManager's unload/reload cycle (see feature request: "make
## sure the memory is well managed... or the game will be unplayable") --
## a chunk far enough from the camera frees itself and everything under it,
## a later regeneration of that same coordinate resumes harvested resource
## amounts, a Village permanently pins its own chunk, and a blob actively
## travelling toward a chunk vetoes unloading it.

const BLOB_SCENE: PackedScene = preload("res://scenes/units/blob/blob.tscn")

## Well past CHUNK_UNLOAD_RADIUS chunks (in world units) from any test
## coordinate used below, so "move the focus here" always means "everything
## near the origin becomes eligible to unload."
const FAR_AWAY := Vector3(50000.0, 0.0, 50000.0)


func _make_chunk_manager(world: Node3D) -> ChunkManager:
	var chunk_manager := ChunkManager.new()
	chunk_manager.setup(world)
	return chunk_manager


func _make_world() -> Node3D:
	var world := Node3D.new()
	add_child(world, true)
	auto_free(world)
	return world


## Scans nearby coordinates for one that actually rolled at least one
## resource node and isn't a village -- resource scattering is random per
## coordinate (even seeded, different coords roll differently), so this
## can't just assume a fixed coordinate always has one.
func _find_coord_with_resources(chunk_manager: ChunkManager) -> Vector2i:
	for dx in range(0, 6):
		for dy in range(0, 6):
			var coord := Vector2i(dx, dy)
			var center := chunk_manager._chunk_center_world(coord)
			chunk_manager.ensure_chunks_loaded(center)
			var chunk: Chunk = chunk_manager.loaded_chunks.get(coord)
			if chunk and chunk._resource_nodes.size() > 0 and not chunk.has_village:
				return coord
	fail("no nearby test coordinate rolled a resource node -- widen the scan range")
	return Vector2i.ZERO


func test_a_far_chunk_unloads_and_a_near_one_stays_loaded() -> void:
	var world := _make_world()
	var chunk_manager := _make_chunk_manager(world)
	var near_coord := Vector2i(0, 0)
	chunk_manager.ensure_chunks_loaded(Vector3.ZERO)

	chunk_manager.process(1.0, FAR_AWAY)

	assert_bool(chunk_manager.loaded_chunks.has(near_coord)).is_false()
	# The far-away focus position's own surrounding chunk should now be
	# loaded instead -- confirms unloading didn't just empty everything out.
	var far_coord := chunk_manager._world_pos_to_chunk_coord(FAR_AWAY)
	assert_bool(chunk_manager.loaded_chunks.has(far_coord)).is_true()


func test_unloading_and_reloading_the_same_coord_resumes_a_harvested_amount() -> void:
	var world := _make_world()
	var chunk_manager := _make_chunk_manager(world)
	var coord := _find_coord_with_resources(chunk_manager)
	var chunk: Chunk = chunk_manager.loaded_chunks[coord]
	var node = chunk._resource_nodes[0]
	var max_amount: int = node.max_amount
	node.harvest(mini(5, max_amount - 1))
	var depleted_amount: int = node.amount
	assert_int(depleted_amount).is_less(max_amount)

	chunk_manager.process(1.0, FAR_AWAY)
	assert_bool(chunk_manager.loaded_chunks.has(coord)).is_false()

	var center := chunk_manager._chunk_center_world(coord)
	chunk_manager.process(1.0, center)
	var reloaded: Chunk = chunk_manager.loaded_chunks.get(coord)
	assert_object(reloaded).is_not_null()
	assert_object(reloaded).is_not_equal(chunk)
	assert_int(reloaded._resource_nodes[0].amount).is_equal(depleted_amount)


func test_a_village_chunk_never_unloads_no_matter_how_far_the_focus_moves() -> void:
	var world := _make_world()
	var chunk_manager := _make_chunk_manager(world)
	var village_coord := Vector2i(-999, -999)
	# Villages are rare (Chunk.VILLAGE_CHANCE) -- scan a wide area to
	# reliably find at least one within a single test run.
	for dx in range(-15, 15):
		for dy in range(-15, 15):
			var coord := Vector2i(dx, dy)
			chunk_manager.ensure_chunks_loaded(chunk_manager._chunk_center_world(coord))
			if chunk_manager.loaded_chunks[coord].has_village:
				village_coord = coord
				break
		if village_coord != Vector2i(-999, -999):
			break
	assert_bool(village_coord != Vector2i(-999, -999)).is_true()

	chunk_manager.process(1.0, FAR_AWAY)

	assert_bool(chunk_manager.loaded_chunks.has(village_coord)).is_true()


func test_a_chunk_a_blob_is_travelling_toward_is_not_unloaded() -> void:
	var world := _make_world()
	var chunk_manager := _make_chunk_manager(world)
	var coord := _find_coord_with_resources(chunk_manager)
	var target := chunk_manager._chunk_center_world(coord)

	var blob: Node3D = BLOB_SCENE.instantiate()
	blob.kind_id = "worker"
	world.add_child(blob, true)
	auto_free(blob)
	# The test's minimal Node3D "world" stand-in doesn't implement the real
	# World's world_to_grid/compute_path facade Blob's own _physics_process
	# duck-types against (see CLAUDE.md's "world.gd" section) -- disabled
	# (after add_child, since _ready() re-enables it) per CLAUDE.md's own
	# testing note on isolating pure state checks like this one from a full
	# physics/pathing simulation this test doesn't need.
	blob.set_physics_process(false)
	blob.global_position = FAR_AWAY
	blob.command_move(target)

	assert_bool(chunk_manager._is_safe_to_unload(chunk_manager.loaded_chunks[coord])).is_false()


func test_a_chunk_no_blob_cares_about_is_safe_to_unload() -> void:
	var world := _make_world()
	var chunk_manager := _make_chunk_manager(world)
	var coord := _find_coord_with_resources(chunk_manager)

	assert_bool(chunk_manager._is_safe_to_unload(chunk_manager.loaded_chunks[coord])).is_true()
