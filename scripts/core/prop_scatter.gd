class_name PropScatter
extends RefCounted
## Stateless helper (see CLAUDE.md "Shared helpers vs. inheritance") that
## builds a chunk's purely-decorative ground clutter: a foliage MultiMesh
## (grass/fern/reed/frost-tuft blade clusters, biome-dependent) plus a
## sparser "accent" MultiMesh (a small stemmed bloom/ember/crystal stud).
## Everything here is cosmetic set dressing with no collision and no
## gameplay meaning -- unlike Biomes.resources (real ResourceNode scenes a
## blob can harvest), a PropScatter prop is never clicked, never
## registered on any group, and never referenced again after being placed.
## Built as plain code-generated primitive meshes (no external assets),
## same convention as every other visual in this project, and batched via
## MultiMeshInstance3D (one draw call per chunk per prop type) since a
## chunk can easily want 50-90 individual blades -- cheap in bulk, wasteful
## as separate scene instances the way Biomes.resources' real resource
## nodes need to be (each of those needs its own script/state; these don't).
##
## Chunk calls build_for_biome() once per chunk (see Chunk._scatter_props)
## and adds whatever nodes come back as its own children.

const GRASS_SHADER: Shader = preload("res://scripts/core/grass.gdshader")

## Per-biome look/density table. Kept as a match-case (like
## Effects.resource_color) rather than a const Dictionary of Color/struct
## literals, since GDScript consts can't easily hold nested Color-keyed
## dictionaries built from constructor calls.
static func _biome_def(biome_id: String) -> Dictionary:
	match biome_id:
		"plains":
			return {
				"tuft_height": 0.32, "tuft_width": 0.11, "tuft_count": 70,
				"tuft_base": Color(0.16, 0.34, 0.12), "tuft_tip": Color(0.48, 0.68, 0.26),
				"bloom_count": 10, "bloom_color": Color(0.95, 0.82, 0.3), "bloom_emissive": false,
			}
		"forest":
			return {
				"tuft_height": 0.4, "tuft_width": 0.12, "tuft_count": 55,
				"tuft_base": Color(0.1, 0.28, 0.1), "tuft_tip": Color(0.32, 0.5, 0.2),
				"bloom_count": 6, "bloom_color": Color(0.85, 0.35, 0.5), "bloom_emissive": false,
			}
		"desert":
			return {
				"tuft_height": 0.22, "tuft_width": 0.09, "tuft_count": 22,
				"tuft_base": Color(0.45, 0.36, 0.16), "tuft_tip": Color(0.72, 0.62, 0.3),
				"bloom_count": 5, "bloom_color": Color(0.9, 0.3, 0.35), "bloom_emissive": false,
			}
		"tundra":
			return {
				"tuft_height": 0.2, "tuft_width": 0.1, "tuft_count": 30,
				"tuft_base": Color(0.65, 0.72, 0.78), "tuft_tip": Color(0.92, 0.95, 0.98),
				"bloom_count": 8, "bloom_color": Color(0.7, 0.88, 1.0), "bloom_emissive": true,
			}
		"swamp":
			return {
				"tuft_height": 0.5, "tuft_width": 0.08, "tuft_count": 45,
				"tuft_base": Color(0.2, 0.24, 0.12), "tuft_tip": Color(0.42, 0.48, 0.22),
				"bloom_count": 6, "bloom_color": Color(0.85, 0.9, 0.75), "bloom_emissive": false,
			}
		"jungle":
			return {
				"tuft_height": 0.48, "tuft_width": 0.16, "tuft_count": 65,
				"tuft_base": Color(0.08, 0.32, 0.1), "tuft_tip": Color(0.3, 0.58, 0.18),
				"bloom_count": 12, "bloom_color": Color(0.9, 0.2, 0.55), "bloom_emissive": false,
			}
		"volcanic":
			return {
				"tuft_height": 0.24, "tuft_width": 0.1, "tuft_count": 18,
				"tuft_base": Color(0.14, 0.12, 0.11), "tuft_tip": Color(0.32, 0.28, 0.25),
				"bloom_count": 9, "bloom_color": Color(1.0, 0.45, 0.1), "bloom_emissive": true,
			}
		_:
			return _biome_def("plains")

## Returns the (0-2) MultiMeshInstance3D nodes a chunk of `biome_id` should
## add as children -- a foliage layer and an accent layer, each possibly
## empty (and therefore omitted) if every scattered candidate point
## happened to land on water. `chunk_half` is the same margin-adjusted
## half-extent Chunk already uses for resource scattering; `world_origin`
## is the chunk's own global (x, z) so candidate points can be tested
## against Biomes.is_water_at in world space.
static func build_for_biome(biome_id: String, chunk_half: float, world_origin: Vector2) -> Array:
	var def := _biome_def(biome_id)
	var result: Array = []

	var tuft_mesh := _build_blade_cluster_mesh(def.tuft_height, def.tuft_width, def.tuft_base, def.tuft_tip)
	var tuft_mat := ShaderMaterial.new()
	tuft_mat.shader = GRASS_SHADER
	tuft_mesh.surface_set_material(0, tuft_mat)
	var tuft_inst := _scatter_multimesh(tuft_mesh, def.tuft_count, chunk_half, world_origin)
	if tuft_inst:
		result.append(tuft_inst)

	var bloom_mesh := _build_bloom_mesh(def.bloom_color)
	var bloom_mat := StandardMaterial3D.new()
	bloom_mat.vertex_color_use_as_albedo = true
	bloom_mat.roughness = 0.55
	if def.bloom_emissive:
		bloom_mat.emission_enabled = true
		bloom_mat.emission = def.bloom_color
		bloom_mat.emission_energy_multiplier = 1.6
	bloom_mesh.surface_set_material(0, bloom_mat)
	var bloom_inst := _scatter_multimesh(bloom_mesh, def.bloom_count, chunk_half, world_origin)
	if bloom_inst:
		result.append(bloom_inst)

	return result

## Scatters `count` random-position/rotation/scale instances of `mesh`
## within [-chunk_half, chunk_half]^2 (local space), skipping any point
## that lands on water, and returns a MultiMeshInstance3D wrapping them --
## or null if every single instance got skipped (a small chunk on a biome
## border sampling mostly water, say), so Chunk doesn't add an empty node.
static func _scatter_multimesh(mesh: ArrayMesh, count: int, chunk_half: float, world_origin: Vector2) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh

	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in count:
		var local := Vector3(randf_range(-chunk_half, chunk_half), 0.0, randf_range(-chunk_half, chunk_half))
		if Biomes.is_water_at(world_origin.x + local.x, world_origin.y + local.z):
			continue
		var s := randf_range(0.75, 1.3)
		var basis := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s, s, s))
		transforms.append(Transform3D(basis, local))
		var tint := randf_range(0.85, 1.15)
		colors.append(Color(tint, tint, tint))

	if transforms.is_empty():
		return null

	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])

	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst

## Builds a small tuft of `blade_count` tapered, single-sided triangle
## blades splayed evenly around Y (each jittered a little for a less
## mechanically-regular tuft), vertex-colored from a darker `base_color` at
## the planted foot to a lighter `tip_color` at the point -- reused as the
## one foliage shape for every biome (grass/fern/reed/frost-tuft/ash-scrub),
## distinguished purely by height/width/color per _biome_def. VERTEX.y at
## each blade's tip is deliberately left as the true local height (not
## renormalized to 0..1) since grass.gdshader reads it directly as its
## wind-sway bend factor.
static func _build_blade_cluster_mesh(height: float, width: float, base_color: Color, tip_color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blade_count := 3
	for i in blade_count:
		var angle := (TAU / blade_count) * i + randf_range(-0.4, 0.4)
		var lean := Vector3(cos(angle), 0.0, sin(angle)) * width * 0.4
		var base_l := Vector3(-width * 0.5, 0.0, 0.0).rotated(Vector3.UP, angle)
		var base_r := Vector3(width * 0.5, 0.0, 0.0).rotated(Vector3.UP, angle)
		var tip := Vector3(0.0, height, 0.0) + lean
		st.set_color(base_color)
		st.add_vertex(base_l)
		st.set_color(base_color)
		st.add_vertex(base_r)
		st.set_color(tip_color)
		st.add_vertex(tip)
	st.generate_normals()
	return st.commit()

## Builds a tiny stemmed bloom -- a thin stalk topped with a small 4-sided
## bipyramid stud, colored `color` throughout -- reused as the sparser
## "accent" prop for every biome (a flower for plains/forest/jungle, a
## cactus-flower for desert, an ice crystal for tundra, a pale bog-flower
## for swamp, a glowing ember for volcanic).
static func _build_bloom_mesh(color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_color := Color(0.25, 0.42, 0.16)
	st.set_color(stem_color)
	st.add_vertex(Vector3(-0.025, 0.0, 0.0))
	st.set_color(stem_color)
	st.add_vertex(Vector3(0.025, 0.0, 0.0))
	st.set_color(stem_color.lerp(color, 0.5))
	st.add_vertex(Vector3(0.0, 0.34, 0.0))

	var center := Vector3(0.0, 0.4, 0.0)
	var r := 0.09
	for i in 4:
		var a0 := (TAU / 4.0) * i
		var a1 := (TAU / 4.0) * (i + 1)
		var p0 := center + Vector3(cos(a0), 0.0, sin(a0)) * r
		var p1 := center + Vector3(cos(a1), 0.0, sin(a1)) * r
		var top := center + Vector3(0.0, r * 0.8, 0.0)
		var bottom := center + Vector3(0.0, -r * 0.5, 0.0)
		st.set_color(color)
		st.add_vertex(p0)
		st.set_color(color)
		st.add_vertex(p1)
		st.set_color(color)
		st.add_vertex(top)
		st.set_color(color)
		st.add_vertex(p1)
		st.set_color(color)
		st.add_vertex(p0)
		st.set_color(color)
		st.add_vertex(bottom)
	st.generate_normals()
	return st.commit()
