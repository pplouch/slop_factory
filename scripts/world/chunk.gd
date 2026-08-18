class_name Chunk
extends Node3D
## One streamed tile of the world map: its own ground mesh (a subtly
## height-jittered, biome-tinted plane) with flat collision for raycasting,
## plus a scatter of that biome's resource nodes. Generated once, the first
## time World notices the camera has come near it (see
## World._ensure_chunks_loaded) -- like Minecraft's chunk loading, but
## deliberately load-only, never unloaded/regenerated: resource nodes
## inside a chunk are live, persistent game objects a blob might already be
## en route to, and freeing them out from under it would be a real bug, not
## just a visual pop.

const CHUNK_SIZE := 25.0
## Higher than a bare-minimum grid needs, so river/lake edges (see
## Biomes.is_water_at) blend reasonably smoothly instead of in blocky
## quantized steps -- terrain relief is purely cosmetic either way (see
## _build_ground_mesh), so the extra vertices are cheap.
const SUBDIVISIONS := 10
## Doubled twice now from the original 32 (see feature backlog: "smooth and
## improve terrain texture", then the "looks low-resolution" pass that also
## added mipmaps -- see _build_ground_material) -- TEXTURE_NOISE_FREQUENCY
## was halved alongside the first doubling so the mottling pattern keeps the
## same physical size per chunk, just resolved at higher pixel density
## (less blocky/pixelated up close, and mip-filterable at a distance).
const TEXTURE_SIZE := 128
const TEXTURE_NOISE_FREQUENCY := 0.09
## Fine-grain detail speckling (see _build_ground_material) -- a pixel whose
## much-higher-frequency detail_noise sample exceeds this threshold gets
## darkened, giving sparse dirt-clump/grain flecks on top of the base
## mottling. Threshold picked high enough that only a small fraction of
## pixels qualify (a sparse scatter of flecks, not a second overlapping
## band pattern).
const DETAIL_SPECKLE_THRESHOLD := 0.55
const DETAIL_SPECKLE_DARKEN := 0.22
## How strongly the generated normal map perturbs lighting (see
## _build_ground_material's second pass) -- tuned by eye against a real-
## renderer screenshot; the base mottling noise varies gently (0..1 over
## many texels), so this needs to be well above 1.0 to read as a visible
## bump rather than a near-flat surface.
const NORMAL_MAP_STRENGTH := 5.0
const GROUND_SHADER: Shader = preload("res://scripts/world/ground.gdshader")

## Resource clusters attempted per chunk (each biome resource entry has an
## independent chance to actually appear, so not every chunk gets one of
## everything its biome offers).
const RESOURCE_ATTEMPT_CHANCE := 0.7
const RESOURCE_CLUSTER_COUNT_RANGE := Vector2i(2, 5)
const RESOURCE_SPAWN_MARGIN := 0.4  # fraction of CHUNK_SIZE kept clear of the very edge

## Chance this chunk also gets a small huddle of Animals (food source).
const ANIMAL_CHANCE := 0.35
const ANIMAL_SCENE: PackedScene = preload("res://scenes/world_objects/animal.tscn")

## Chance this chunk gets a single lootable Chest (see feature backlog:
## "add chests and scatter them on the map") -- deliberately rarer than
## Animal's own huddle chance, since a chest's one-time haul is meant to
## read as a small find, not an everyday feature of the landscape.
const CHEST_CHANCE := 0.1
const CHEST_SCENE: PackedScene = preload("res://scenes/world_objects/chest.tscn")

## Chance this chunk gets a single Village (see feature backlog: "add
## friendly villages to trade with" / "add unfriendly enemy villages to
## steal resources from") -- deliberately rarer than even Chest, since a
## village is a real landmark (a small guarded outpost, or a repeatable
## trade post) rather than a one-time pickup. Evenly split between the two
## kinds once the roll succeeds at all.
const VILLAGE_CHANCE := 0.03
const FRIENDLY_VILLAGE_SCENE: PackedScene = preload("res://scenes/world_objects/friendly_village.tscn")
const ENEMY_VILLAGE_SCENE: PackedScene = preload("res://scenes/world_objects/enemy_village.tscn")

## Chance this chunk gets a single SlotMachine (see feature backlog:
## "wanky dandy" fun features/mini-games) -- between Chest and Village in
## rarity, since it's a fun little distraction rather than either an
## everyday pickup or a real landmark.
const SLOT_MACHINE_CHANCE := 0.05
const SLOT_MACHINE_SCENE: PackedScene = preload("res://scenes/world_objects/slot_machine.tscn")

## Lakes are placed procedurally (see Biomes.is_lake_at) rather than at a
## flat per-chunk chance -- a chunk only gets a harvestable water source if
## one of a few sampled points inside it actually lands on lake terrain, so
## water reads as following the same broad lakes the ground tinting shows
## instead of scattering puddles anywhere. Rivers used to also spawn a
## small "puddle" pond (`water_pond.tscn`) at any crossing, removed since
## the river itself already reads as water via the ground's own tint/shore-
## foam shader (see Biomes.water_tint_at/shore_factor_at) without needing a
## separate harvestable object cluttering every crossing -- Lake remains
## the sole harvestable "water" resource_type source.
const WATER_PLACEMENT_ATTEMPTS := 6
const LAKE_SCENE: PackedScene = preload("res://scenes/world_objects/lake.tscn")

var biome: Biomes.Biome
var chunk_coord: Vector2i


## Builds this chunk's ground and scenery. `coord` is used only to seed
## per-chunk randomness deterministically (not strictly required since
## chunks never regenerate, but keeps a given coordinate's *shape*
## reproducible if ever needed for debugging). Must be called after this
## node is already positioned in the tree (global_position must be final)
## since ground-height/river/lake sampling all read world-space positions
## for seamless continuity across chunk borders.
func generate(coord: Vector2i, p_biome: Biomes.Biome) -> void:
	chunk_coord = coord
	biome = p_biome
	_build_ground()
	_scatter_resources()
	_scatter_props()
	_spawn_ambient_particles()
	_maybe_spawn_water()
	if randf() < ANIMAL_CHANCE:
		var count := randi_range(1, 3)
		for i in count:
			_spawn_one(ANIMAL_SCENE)
	if randf() < CHEST_CHANCE:
		_maybe_spawn_chest()
	if randf() < VILLAGE_CHANCE:
		_maybe_spawn_village()
	if randf() < SLOT_MACHINE_CHANCE:
		_maybe_spawn_slot_machine()

## Builds the ground mesh (height-displaced plane, biome-tinted procedural
## texture) and a matching flat collision box for raycasting -- the
## collision stays flat regardless of visual bumps, so every existing
## ground-raycast system (click-to-move, grid placement) is unaffected by
## the cosmetic relief.
func _build_ground() -> void:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = _build_ground_mesh()
	add_child(mesh_inst)

	var body := StaticBody3D.new()
	body.collision_layer = 1  # Ground
	body.collision_mask = 0
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(CHUNK_SIZE, 1.0, CHUNK_SIZE)
	collision.shape = shape
	collision.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(collision)

## Starts from a normal subdivided PlaneMesh (guaranteed-correct winding/
## UVs), displaces only its vertices' Y using the shared, world-space-
## sampled Biomes.height_at (so height agrees with whatever any neighboring
## chunk already computed for the same border vertex), and tints vertices
## with `Biomes.blended_ground_color_at(...) * Biomes.water_tint_at(...)` --
## the former a continuously-blended biome color (see that function's own
## header on why this needs to be a per-*vertex* value rather than baked
## into the chunk's own tiled procedural texture: a texture repeats within
## one chunk and so can never carry a whole-chunk-spanning gradient, while
## vertex colors interpolate smoothly and agree exactly with a neighboring
## chunk's own mesh at their shared border, since both sample the same
## continuous world-space function), the latter white on dry land, smoothly
## blending through a sandy shore ring and into shallow/deep water as the
## underlying noise approaches and passes its water threshold (see feature
## backlog: "water ridge should have a texture on the borders to make it
## more realistic") -- multiplying the two together means water still reads
## as its own tint near the shore (water_tint_at dominates there) while dry
## land shows the smooth biome blend (water_tint_at is pure white away from
## water, a no-op multiply). Both are purely cosmetic terrain relief/color --
## Blob/Enemy's global_position.y stays force-clamped to 0.0 every physics
## frame regardless (see CLAUDE.md: "this project has no vertical
## gameplay"), so this never has to agree with unit footing, just look
## pleasant from the RTS camera angle. Vertex-color alpha separately carries
## Biomes.shore_factor_at -- unused by anything reading the tint as a
## color, but read by ground.gdshader as its animated-foam mask.
func _build_ground_mesh() -> ArrayMesh:
	var plane := PlaneMesh.new()
	plane.size = Vector2(CHUNK_SIZE, CHUNK_SIZE)
	plane.subdivide_width = SUBDIVISIONS
	plane.subdivide_depth = SUBDIVISIONS

	var arrays: Array = plane.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	colors.resize(vertices.size())

	for i in vertices.size():
		var v := vertices[i]
		var world_x := global_position.x + v.x
		var world_z := global_position.z + v.z
		var height: float = Biomes.height_at(world_x, world_z)
		vertices[i] = Vector3(v.x, height, v.z)
		var biome_blend: Color = Biomes.blended_ground_color_at(world_x, world_z)
		var tint: Color = Biomes.water_tint_at(world_x, world_z)
		var shore: float = Biomes.shore_factor_at(world_x, world_z)
		colors[i] = Color(biome_blend.r * tint.r, biome_blend.g * tint.g, biome_blend.b * tint.b, shore)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors

	var base_mesh := ArrayMesh.new()
	base_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	base_mesh.surface_set_material(0, _build_ground_material())

	var st := SurfaceTool.new()
	st.create_from(base_mesh, 0)
	st.generate_normals()
	return st.commit()

## Neutral gray reference the procedural texture's own light/dark mottling
## darkens/lightens around -- deliberately *not* biome.ground_color (see
## this method's own header): the actual hue now comes entirely from the
## per-vertex Biomes.blended_ground_color_at multiply in ground.gdshader,
## so the texture itself only ever needs to carry grayscale
## brightness variation, the same way a real terrain shader separates a
## grayscale detail/roughness texture from a vertex-painted base color.
const TEXTURE_NEUTRAL_BASE := Color(0.92, 0.92, 0.92)

## Builds a small procedurally-mottled *grayscale* texture (light/dark noise
## bands around TEXTURE_NEUTRAL_BASE, the same "generate an Image by hand"
## technique BeltSegment uses for its stripe texture) so the ground reads as
## textured terrain rather than a flat color swatch, plus a second,
## much higher-frequency DETAIL_NOISE layer sparsely darkening scattered
## pixels on top -- reads as small dirt clumps/pebble grain breaking up the
## base mottling's otherwise fairly uniform band pattern, the same "layer a
## finer-scale pass on top" idea TEXTURE_NOISE_FREQUENCY's own fractal
## octaves already use, just at a scale coarse noise octaves alone don't
## reach. Vertex colors (see _build_ground_mesh) multiply on top of this via
## ground.gdshader, tinting river/lake vertices blue without needing a
## second, position-sampled texture, and also drive that shader's animated
## shoreline foam (see its own header). On volcanic ground specifically,
## those same detail-noise pixels also seed the texture's *alpha* channel
## as an "ember" mask (1.0, else 0.0 everywhere on every other biome) --
## ground.gdshader reads that mask to pulse a glowing crack there, purely a
## volcanic-flavor bonus riding on noise samples this function was already
## computing per pixel anyway.
##
## Also builds a matching normal map, derived from the same base-mottling
## noise field via a central-difference pass (a texel's "height" is just
## its own `n` sample, reused as a cheap pseudo-heightfield) -- without
## this, the ground previously lit as a perfectly flat surface with a
## painted-on color pattern, which read as flat/plasticky/"low-resolution"
## regardless of how sharp the color texture itself was. Both images call
## `generate_mipmaps()` before becoming textures (see feature request:
## "the textures... look low-resolution") -- `ImageTexture.create_from_image`
## does not generate mips on its own, so despite `ground.gdshader` already
## sampling with `filter_linear_mipmap`, there was previously only ever a
## single mip level to filter, which shows up as shimmering/aliasing at a
## distance rather than smoothly blurring like a normal textured surface.
func _build_ground_material() -> ShaderMaterial:
	var img := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var normal_img := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGB8)
	var tex_noise := FastNoiseLite.new()
	tex_noise.seed = hash(chunk_coord) + 1
	tex_noise.frequency = TEXTURE_NOISE_FREQUENCY
	# A little fractal detail layered on top of the base mottling reads as
	# more organic/less uniformly speckled than a single noise frequency --
	# gain kept modest so it adds texture without overwhelming the base
	# pattern's scale.
	tex_noise.fractal_octaves = 3
	tex_noise.fractal_lacunarity = 2.0
	tex_noise.fractal_gain = 0.4

	var detail_noise := FastNoiseLite.new()
	detail_noise.seed = hash(chunk_coord) + 2
	detail_noise.frequency = TEXTURE_NOISE_FREQUENCY * 3.5
	var is_volcanic := biome.id == "volcanic"

	var heights := PackedFloat32Array()
	heights.resize(TEXTURE_SIZE * TEXTURE_SIZE)

	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var n: float = (tex_noise.get_noise_2d(x, y) + 1.0) * 0.5
			heights[y * TEXTURE_SIZE + x] = n
			var shade: Color = TEXTURE_NEUTRAL_BASE.darkened(0.12).lerp(TEXTURE_NEUTRAL_BASE.lightened(0.12), n)
			var detail: float = detail_noise.get_noise_2d(x, y)
			var ember := 0.0
			if detail > DETAIL_SPECKLE_THRESHOLD:
				shade = shade.darkened(DETAIL_SPECKLE_DARKEN)
				if is_volcanic:
					ember = 1.0
			img.set_pixel(x, y, Color(shade.r, shade.g, shade.b, ember))

	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var xl := maxi(x - 1, 0)
			var xr := mini(x + 1, TEXTURE_SIZE - 1)
			var yd := maxi(y - 1, 0)
			var yu := mini(y + 1, TEXTURE_SIZE - 1)
			var dx: float = (heights[y * TEXTURE_SIZE + xr] - heights[y * TEXTURE_SIZE + xl]) * NORMAL_MAP_STRENGTH
			var dy: float = (heights[yu * TEXTURE_SIZE + x] - heights[yd * TEXTURE_SIZE + x]) * NORMAL_MAP_STRENGTH
			var normal := Vector3(-dx, -dy, 1.0).normalized()
			normal_img.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5))

	img.generate_mipmaps()
	normal_img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	var normal_tex := ImageTexture.create_from_image(normal_img)

	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("albedo_texture", tex)
	mat.set_shader_parameter("normal_texture", normal_tex)
	mat.set_shader_parameter("uv_scale", Vector2(4.0, 4.0))
	return mat

## Scatters a handful of small resource clusters using this chunk's
## biome's resource list (see Biomes.Biome.resources) -- each resource
## entry independently has RESOURCE_ATTEMPT_CHANCE of appearing at all in
## this particular chunk, so neighboring chunks of the same biome still
## look varied rather than identically populated. Both that chance and how
## many clusters actually appear are additionally scaled by
## Biomes.resource_abundance_multiplier_at (see feature request: "the
## farther the biome is, the rarer the resources") -- 1.0 near the origin,
## dropping toward Biomes.MIN_RESOURCE_ABUNDANCE_MULT out at
## Biomes.DIFFICULTY_MAX_DISTANCE, so resources read as progressively
## scarcer with distance on top of however common this biome's own resource
## list already makes them.
func _scatter_resources() -> void:
	var half := CHUNK_SIZE * 0.5 * (1.0 - RESOURCE_SPAWN_MARGIN)
	var abundance: float = Biomes.resource_abundance_multiplier_at(global_position.x, global_position.z)
	for entry in biome.resources:
		if randf() > RESOURCE_ATTEMPT_CHANCE * abundance:
			continue
		var count := maxi(1, roundi(randi_range(RESOURCE_CLUSTER_COUNT_RANGE.x, RESOURCE_CLUSTER_COUNT_RANGE.y) * abundance))
		for i in count:
			var inst: Node3D = entry.scene.instantiate()
			add_child(inst)
			inst.position = Vector3(randf_range(-half, half), 0.0, randf_range(-half, half))
			inst.rotation.y = randf() * TAU
			var s := randf_range(0.85, 1.25)
			inst.scale = Vector3(s, s, s)

## Scatters this biome's purely-decorative foliage/bloom props (see
## PropScatter) -- unlike _scatter_resources, these are never harvestable
## and carry no state, so they're batched as MultiMeshInstance3D nodes
## rather than individual scene instances.
func _scatter_props() -> void:
	var half := CHUNK_SIZE * 0.5 * (1.0 - RESOURCE_SPAWN_MARGIN)
	var origin := Vector2(global_position.x, global_position.z)
	for node in PropScatter.build_for_biome(biome.id, half, origin):
		add_child(node)

## Adds this biome's small ambient drifting-particle effect (see
## AmbientParticles) -- offset up to roughly chest height so the emission
## box sits mostly above the ground/props rather than half-buried in it.
func _spawn_ambient_particles() -> void:
	var half := CHUNK_SIZE * 0.5
	var particles := AmbientParticles.build_for_biome(biome.id, half)
	add_child(particles)
	particles.position = Vector3(0.0, 1.2, 0.0)

## Tries a few random points within this chunk (see WATER_PLACEMENT_ATTEMPTS)
## and, the first time one actually lands on lake terrain (see
## Biomes.is_lake_at), spawns a harvestable Lake there. Most chunks sample
## none and get no water source at all, since lakes are a localized
## procedural feature rather than a flat chance anywhere -- a river
## crossing a chunk no longer spawns anything here (see WATER_PLACEMENT_ATTEMPTS'
## own comment), it's purely the ground's own tint/shore-foam doing the work.
func _maybe_spawn_water() -> void:
	var half := CHUNK_SIZE * 0.5 * (1.0 - RESOURCE_SPAWN_MARGIN)
	for attempt in WATER_PLACEMENT_ATTEMPTS:
		var local := Vector3(randf_range(-half, half), 0.0, randf_range(-half, half))
		var world_x := global_position.x + local.x
		var world_z := global_position.z + local.z
		if Biomes.is_lake_at(world_x, world_z):
			var inst: Node3D = LAKE_SCENE.instantiate()
			add_child(inst)
			inst.position = local
			return

## Spawns one instance of `scene` at a random point within this chunk.
func _spawn_one(scene: PackedScene) -> void:
	var half := CHUNK_SIZE * 0.5 * (1.0 - RESOURCE_SPAWN_MARGIN)
	var inst: Node3D = scene.instantiate()
	add_child(inst)
	inst.position = Vector3(randf_range(-half, half), 0.0, randf_range(-half, half))

## Spawns one Chest at a random point in this chunk (see CHEST_CHANCE) --
## skipped entirely if the rolled spot happens to land on water, rather
## than a chest floating in a lake (no retry, unlike _maybe_spawn_water's
## several attempts -- a chest simply not appearing in this particular
## chunk is a fine outcome given how rare it already is).
func _maybe_spawn_chest() -> void:
	var half := CHUNK_SIZE * 0.5 * (1.0 - RESOURCE_SPAWN_MARGIN)
	var local := Vector3(randf_range(-half, half), 0.0, randf_range(-half, half))
	if Biomes.is_water_at(global_position.x + local.x, global_position.z + local.z):
		return
	var inst: Node3D = CHEST_SCENE.instantiate()
	add_child(inst)
	inst.position = local
	inst.rotation.y = randf() * TAU

## Spawns one Village at a random point in this chunk (see VILLAGE_CHANCE),
## an even coin flip between friendly and enemy -- skipped entirely if the
## rolled spot lands on water, same no-retry convention as
## _maybe_spawn_chest.
func _maybe_spawn_village() -> void:
	var half := CHUNK_SIZE * 0.5 * (1.0 - RESOURCE_SPAWN_MARGIN)
	var local := Vector3(randf_range(-half, half), 0.0, randf_range(-half, half))
	if Biomes.is_water_at(global_position.x + local.x, global_position.z + local.z):
		return
	var scene: PackedScene = FRIENDLY_VILLAGE_SCENE if randf() < 0.5 else ENEMY_VILLAGE_SCENE
	var inst: Node3D = scene.instantiate()
	add_child(inst)
	inst.position = local
	inst.rotation.y = randf() * TAU

## Spawns one SlotMachine at a random point in this chunk (see
## SLOT_MACHINE_CHANCE) -- skipped entirely if the rolled spot lands on
## water, same no-retry convention as _maybe_spawn_chest/_maybe_spawn_village.
func _maybe_spawn_slot_machine() -> void:
	var half := CHUNK_SIZE * 0.5 * (1.0 - RESOURCE_SPAWN_MARGIN)
	var local := Vector3(randf_range(-half, half), 0.0, randf_range(-half, half))
	if Biomes.is_water_at(global_position.x + local.x, global_position.z + local.z):
		return
	var inst: Node3D = SLOT_MACHINE_SCENE.instantiate()
	add_child(inst)
	inst.position = local
	inst.rotation.y = randf() * TAU
