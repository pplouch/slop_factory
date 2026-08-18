extends GdUnitTestSuite
## Covers PropScatter: builds decorative foliage/bloom MultiMeshInstance3D
## layers for a chunk. world_origin is kept near the true world origin
## (well inside Biomes.WATER_SAFE_RADIUS) so no scattered candidate point
## can randomly land on water and get skipped -- keeps these tests
## deterministic instead of occasionally flaky.

func test_build_for_biome_returns_multimesh_nodes_for_every_registered_biome() -> void:
	for biome_id in Biomes.get_ordered_ids():
		var nodes := PropScatter.build_for_biome(biome_id, 10.0, Vector2.ZERO)
		assert_int(nodes.size()).is_equal(2)
		for node in nodes:
			assert_bool(node is MultiMeshInstance3D).is_true()
			assert_int((node as MultiMeshInstance3D).multimesh.instance_count).is_greater(0)
			auto_free(node)


func test_unknown_biome_id_falls_back_to_the_same_shape_as_plains() -> void:
	var nodes_unknown := PropScatter.build_for_biome("not_a_real_biome", 10.0, Vector2.ZERO)
	var nodes_plains := PropScatter.build_for_biome("plains", 10.0, Vector2.ZERO)
	assert_int(nodes_unknown.size()).is_equal(nodes_plains.size())
	for node in nodes_unknown + nodes_plains:
		auto_free(node)
