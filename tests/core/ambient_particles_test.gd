extends GdUnitTestSuite
## Covers AmbientParticles: builds a small configured GPUParticles3D for
## every biome (every biome currently gets one, see its own header).

func test_build_for_biome_returns_a_configured_particle_system_for_every_biome() -> void:
	for biome_id in Biomes.get_ordered_ids():
		var particles := AmbientParticles.build_for_biome(biome_id, 10.0)
		auto_free(particles)
		assert_int(particles.amount).is_equal(AmbientParticles.AMOUNT)
		assert_object(particles.process_material).is_not_null()
		assert_object(particles.draw_pass_1).is_not_null()


func test_unknown_biome_id_still_returns_a_valid_particle_system() -> void:
	var particles := AmbientParticles.build_for_biome("not_a_real_biome", 10.0)
	auto_free(particles)
	assert_int(particles.amount).is_equal(AmbientParticles.AMOUNT)
