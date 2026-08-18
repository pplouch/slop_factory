extends GdUnitTestSuite
## Covers Chunk's ground-material ember mask (see feature request: "add
## more shaders" -> volcanic ember glow): Chunk.generate() takes its biome
## as a direct parameter rather than deriving it from position, so these
## tests can force any position to be treated as volcanic (or not) without
## needing to actually locate real volcanic terrain first.

func _ember_pixel_count(chunk: Chunk) -> int:
	var mesh_inst: MeshInstance3D = chunk.get_child(0)
	var mat: ShaderMaterial = mesh_inst.mesh.surface_get_material(0)
	var tex: ImageTexture = mat.get_shader_parameter("albedo_texture")
	var img := tex.get_image()
	var count := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				count += 1
	return count


func test_volcanic_ground_material_has_ember_pixels() -> void:
	var chunk := Chunk.new()
	add_child(chunk, true)
	auto_free(chunk)
	chunk.global_position = Vector3(3000.0, 0.0, 3000.0)
	chunk.generate(Vector2i(300, 300), Biomes.get_biome("volcanic"))

	assert_int(_ember_pixel_count(chunk)).is_greater(0)


func test_non_volcanic_ground_material_has_no_ember_pixels() -> void:
	var chunk := Chunk.new()
	add_child(chunk, true)
	auto_free(chunk)
	chunk.global_position = Vector3(3100.0, 0.0, 3100.0)
	chunk.generate(Vector2i(310, 310), Biomes.get_biome("plains"))

	assert_int(_ember_pixel_count(chunk)).is_equal(0)


func test_ground_material_texture_size_matches_chunk_constant() -> void:
	var chunk := Chunk.new()
	add_child(chunk, true)
	auto_free(chunk)
	chunk.global_position = Vector3(3200.0, 0.0, 3200.0)
	chunk.generate(Vector2i(320, 320), Biomes.get_biome("desert"))

	var mesh_inst: MeshInstance3D = chunk.get_child(0)
	var mat: ShaderMaterial = mesh_inst.mesh.surface_get_material(0)
	var tex: ImageTexture = mat.get_shader_parameter("albedo_texture")
	assert_int(tex.get_width()).is_equal(Chunk.TEXTURE_SIZE)
	assert_int(tex.get_height()).is_equal(Chunk.TEXTURE_SIZE)
