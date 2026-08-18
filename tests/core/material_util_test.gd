extends GdUnitTestSuite
## Covers MaterialUtil.duplicated_material: the "duplicate before recolor"
## pattern used throughout the project (Blob's body tint, per-instance ring
## colors, ...) so recoloring one instance never bleeds into every other
## node sharing the same base mesh resource.

func test_duplicated_material_is_a_distinct_instance_with_matching_starting_values() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 0.9)
	var mesh := BoxMesh.new()
	mesh.material = mat
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	auto_free(mesh_inst)

	var duplicate := MaterialUtil.duplicated_material(mesh_inst)

	assert_object(duplicate).is_not_same(mat)
	assert_that(duplicate.albedo_color).is_equal(Color(0.3, 0.6, 0.9))


func test_recoloring_the_duplicate_does_not_affect_the_shared_original() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.RED
	var mesh := BoxMesh.new()
	mesh.material = mat
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	auto_free(mesh_inst)

	var duplicate := MaterialUtil.duplicated_material(mesh_inst)
	duplicate.albedo_color = Color.BLUE

	assert_that(mat.albedo_color).is_equal(Color.RED)
	assert_that(mesh_inst.mesh.material.albedo_color).is_equal(Color.RED)
