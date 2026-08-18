class_name AmbientParticles
extends RefCounted
## Stateless helper building one small, self-contained ambient particle
## effect per chunk (fireflies drifting through a forest/swamp, dust haze
## over a desert/volcanic floor, pollen over plains/jungle, drifting snow
## flecks over tundra) -- purely atmospheric set dressing, like
## PropScatter's foliage/blooms, with no gameplay meaning. Every biome gets
## something, at a small enough amount (see AMOUNT) that a chunk full of
## them still reads as "a bit of drifting motion in the air" rather than a
## visual-noise wall once several chunks are loaded at once (see
## ChunkManager.CHUNK_LOAD_RADIUS -- up to ~49 chunks concurrently).

const AMOUNT := 10
const LIFETIME := 7.0

## Color (and, implicitly, "does this biome get an ambient effect at all" --
## every biome currently does) per biome id. A separate small table from
## PropScatter's, since the effect here is about the air, not the ground.
static func _biome_color(biome_id: String) -> Color:
	match biome_id:
		"forest", "swamp":
			return Color(0.85, 0.95, 0.35)
		"jungle":
			return Color(1.0, 0.85, 0.3)
		"desert":
			return Color(0.85, 0.65, 0.35)
		"volcanic":
			return Color(1.0, 0.45, 0.15)
		"tundra":
			return Color(0.92, 0.96, 1.0)
		"plains":
			return Color(1.0, 0.95, 0.7)
		_:
			return Color(1.0, 1.0, 1.0)

## Builds a GPUParticles3D covering roughly a chunk_half-sized square,
## drifting small glowing motes upward at a lazy pace -- caller (Chunk)
## positions/parents it and is responsible for offsetting it upward (the
## emission box is centered on this node's own origin).
static func build_for_biome(biome_id: String, chunk_half: float) -> GPUParticles3D:
	var color := _biome_color(biome_id)

	var process_mat := ParticleProcessMaterial.new()
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_mat.emission_box_extents = Vector3(chunk_half, 1.0, chunk_half)
	process_mat.direction = Vector3(0.0, 1.0, 0.0)
	process_mat.spread = 60.0
	process_mat.gravity = Vector3(0.0, 0.03, 0.0)
	process_mat.initial_velocity_min = 0.05
	process_mat.initial_velocity_max = 0.2
	process_mat.scale_min = 0.05
	process_mat.scale_max = 0.11
	process_mat.color = color

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.15, 0.15)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	mesh.material = mat

	var particles := GPUParticles3D.new()
	particles.amount = AMOUNT
	particles.lifetime = LIFETIME
	particles.randomness = 1.0
	particles.process_material = process_mat
	particles.draw_pass_1 = mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles
