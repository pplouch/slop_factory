extends GdUnitTestSuite
## Covers GemSparkle: only a MeshInstance3D whose material is a
## StandardMaterial3D with emission_enabled converts to the shared
## animated ShaderMaterial -- a plain (non-emissive) mesh must be left
## completely untouched.

func test_converts_only_the_emissive_mesh_and_carries_its_values_forward() -> void:
	var root := Node3D.new()
	auto_free(root)

	var emissive_mat := StandardMaterial3D.new()
	emissive_mat.emission_enabled = true
	emissive_mat.albedo_color = Color(1.0, 0.5, 0.1)
	emissive_mat.emission = Color(1.0, 0.4, 0.05)
	emissive_mat.emission_energy_multiplier = 2.0
	emissive_mat.metallic = 0.3
	emissive_mat.roughness = 0.4
	var emissive_mesh := SphereMesh.new()
	emissive_mesh.material = emissive_mat
	var emissive_inst := MeshInstance3D.new()
	emissive_inst.mesh = emissive_mesh
	root.add_child(emissive_inst)

	var plain_mat := StandardMaterial3D.new()
	plain_mat.albedo_color = Color(0.2, 0.2, 0.2)
	var plain_mesh := BoxMesh.new()
	plain_mesh.material = plain_mat
	var plain_inst := MeshInstance3D.new()
	plain_inst.mesh = plain_mesh
	root.add_child(plain_inst)

	GemSparkle.apply_to_emissive_meshes(root)

	var converted := emissive_inst.get_surface_override_material(0)
	assert_bool(converted is ShaderMaterial).is_true()
	var shader_mat := converted as ShaderMaterial
	# Compared with is_equal_approx, not exact equality -- a shader uniform
	# float is stored 32-bit, so reading it back promotes to a 64-bit double
	# that isn't bit-identical to the original GDScript double literal.
	assert_float(shader_mat.get_shader_parameter("emission_energy")).is_equal_approx(2.0, 0.0001)
	assert_float(shader_mat.get_shader_parameter("metallic_value")).is_equal_approx(0.3, 0.0001)
	assert_float(shader_mat.get_shader_parameter("roughness_value")).is_equal_approx(0.4, 0.0001)
	assert_that(shader_mat.get_shader_parameter("emission_color")).is_equal(Color(1.0, 0.4, 0.05))

	assert_object(plain_inst.get_surface_override_material(0)).is_null()


func test_running_twice_is_a_safe_no_op_the_second_time() -> void:
	# apply_to_emissive_meshes only inspects a node's *children* (matching
	# every real call site: ResourceNode/Blob/SlotMachine._ready() all pass
	# `self`, with the actual meshes as children) -- so the emissive mesh
	# here must be a child of some root, not the node passed in directly.
	var root := Node3D.new()
	auto_free(root)
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	var mesh := SphereMesh.new()
	mesh.material = mat
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	root.add_child(mesh_inst)

	GemSparkle.apply_to_emissive_meshes(root)
	var first_conversion := mesh_inst.get_surface_override_material(0)
	GemSparkle.apply_to_emissive_meshes(root)
	var second_pass := mesh_inst.get_surface_override_material(0)

	assert_object(second_pass).is_same(first_conversion)
