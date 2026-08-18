extends GdUnitTestSuite
## Covers Blob's torch (see feature request: "make units carry torches to
## see around them" -- night was reported as too dark) and its stat
## scaling across BlobKinds archetypes.

const BLOB_SCENE: PackedScene = preload("res://scenes/units/blob/blob.tscn")


func _spawn_blob(kind_id: String) -> Node3D:
	var blob: Node3D = BLOB_SCENE.instantiate()
	blob.kind_id = kind_id
	add_child(blob, true)
	auto_free(blob)
	return blob


func test_blob_carries_a_lit_torch() -> void:
	var blob := _spawn_blob("worker")
	var torch_light: OmniLight3D = blob.get_node("Visuals/LeftArmPivot/TorchPivot/TorchLight")
	assert_object(torch_light).is_not_null()
	assert_float(torch_light.light_energy).is_greater(0.0)
	assert_float(torch_light.omni_range).is_greater(0.0)


func test_torch_flame_is_converted_to_the_animated_sparkle_shader() -> void:
	# Blob._ready() calls GemSparkle.apply_to_emissive_meshes(self) -- the
	# flame's originally-static emissive material should come out as the
	# shared animated ShaderMaterial, same as every ore/crystal.
	var blob := _spawn_blob("worker")
	var flame: MeshInstance3D = blob.get_node("Visuals/LeftArmPivot/TorchPivot/TorchFlame")
	assert_bool(flame.get_surface_override_material(0) is ShaderMaterial).is_true()


func test_brute_hits_harder_than_worker() -> void:
	# A quick regression check that per-kind multipliers actually reach the
	# final computed stat, not just that BlobKinds' own data table has
	# different numbers on paper.
	var worker := _spawn_blob("worker")
	var brute := _spawn_blob("brute")
	assert_float(brute.attack_power).is_greater(worker.attack_power)
