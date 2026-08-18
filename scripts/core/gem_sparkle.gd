class_name GemSparkle
extends RefCounted
## Stateless helper (see CLAUDE.md "Shared helpers vs. inheritance"):
## finds every MeshInstance3D under a node whose active material is a
## StandardMaterial3D with emission_enabled set -- every ore nugget/vein/
## shard/facet, ice crystal, obsidian ember, and Slopium's own glowing
## body was already hand-authored with that flag on, as the "this bit is
## the valuable/glowing part" marker -- and swaps it for a shared animated
## ShaderMaterial (gem_sparkle.gdshader) carrying the same albedo/
## emission/metallic/roughness values forward as uniforms. Called once
## from ResourceNode._ready(), so every existing ore/crystal scene gets a
## traveling sparkle instead of a static glow with zero per-scene changes.
##
## Uses MeshInstance3D.set_surface_override_material rather than mutating
## mesh.material directly -- the override lives on the *node*, so it's
## always safe per-instance even though sibling meshes (e.g. iron_ore's
## VeinA/VeinB) or even every instance of the same ore across the whole
## map share the same underlying Mesh/StandardMaterial3D sub-resource (see
## CLAUDE.md's PrimitiveMesh/surface_material_override gotcha -- that one
## is about mutating a *freshly-created* mesh's own material the same
## frame, a different situation from overriding an already-scene-loaded
## mesh's *display* material per node).

const SHADER: Shader = preload("res://scripts/core/gem_sparkle.gdshader")

## Recursively walks `node`'s descendants converting every emissive
## MeshInstance3D found. Safe to call on any resource node regardless of
## kind -- one without any emission_enabled mesh (plain wood/stone/food/
## water) just finds nothing to convert.
static func apply_to_emissive_meshes(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			_maybe_convert(child)
		apply_to_emissive_meshes(child)

## Converts a single MeshInstance3D's material if (and only if) it's a
## StandardMaterial3D with emission enabled -- anything else (a plain
## non-glowing rock body, an already-converted mesh on a second pass,
## a mesh with no material at all) is left untouched.
static func _maybe_convert(mesh_inst: MeshInstance3D) -> void:
	var mat: Material = mesh_inst.get_surface_override_material(0)
	if mat == null and mesh_inst.mesh != null:
		mat = mesh_inst.mesh.surface_get_material(0)
	if not (mat is StandardMaterial3D) or not (mat as StandardMaterial3D).emission_enabled:
		return
	var std_mat := mat as StandardMaterial3D

	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = SHADER
	shader_mat.set_shader_parameter("albedo_color", std_mat.albedo_color)
	shader_mat.set_shader_parameter("emission_color", std_mat.emission)
	shader_mat.set_shader_parameter("emission_energy", std_mat.emission_energy_multiplier)
	shader_mat.set_shader_parameter("metallic_value", std_mat.metallic)
	shader_mat.set_shader_parameter("roughness_value", std_mat.roughness)
	shader_mat.set_shader_parameter("alpha", std_mat.albedo_color.a)
	mesh_inst.set_surface_override_material(0, shader_mat)
