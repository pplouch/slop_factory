class_name Chunk
extends Node3D
## One streamed tile of the world map: its own ground mesh (a subtly
## height-jittered, biome-tinted plane) with flat collision for raycasting,
## plus a scatter of that biome's resource nodes. Generated the first time
## World notices the camera has come near it (see ChunkManager.
## ensure_chunks_loaded), and freed again once the camera has moved far
## enough away (see ChunkManager._unload_far_chunks) -- unlike Minecraft's
## own "unloaded chunks just aren't simulated", this project has no on-disk
## save format for world state, so every generate() call (first-time or a
## reload after unloading) must reproduce the *exact* same content for a
## given `coord`, deterministically, or a returning player would see a
## different set of resources/chest/etc. than they left. See _rng's own
## header for how that determinism is achieved, and snapshot_state/
## restore_state for how harvested amounts/loot survive the round trip.
##
## ChunkManager never unloads a chunk that placed a Village (see
## has_village) or that any blob is currently standing in or travelling
## toward -- see ChunkManager's own header for why.

const CHUNK_SIZE := 25.0
## Governs the smoothness of the (purely cosmetic) height/biome-color
## terrain relief baked into vertex data (see _build_ground_mesh) -- water's
## own coastline/shore edge used to also ride on this same per-vertex
## resolution and aliased badly (see feature request: "coastlines are
## straight... unorganic squared coast") wherever the underlying noise
## crossed its threshold within less than one vertex spacing; that's now
## baked into a dedicated, much finer non-tiling per-chunk texture instead
## (see WATER_MASK_SIZE/_build_ground_material), so this constant no longer
## needs to be pushed higher just for water's sake.
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

var biome: Biomes.Biome
var chunk_coord: Vector2i

## Seeded from `hash(chunk_coord)` at the top of generate() -- every content
## -placement roll in this file (resource clusters, animals, chest/village/
## slot-machine spawn + position/rotation/scale) reads from this instead of
## the global randf()/randi_range(), so regenerating the same `coord` after
## an unload always reproduces the exact same sequence of objects rather
## than a fresh, different roll. Purely decorative content with no state to
## lose (PropScatter foliage, AmbientParticles) still uses the global RNG --
## reseeding those too would just be extra plumbing for a difference no
## player could actually notice.
var _rng := RandomNumberGenerator.new()

## Every ResourceNode-derived instance this chunk creates (trees/rocks/ore
## from _scatter_resources, Animal from the huddle loop below), in creation
## order -- since generation is fully deterministic (see _rng), regenerating
## this same chunk_coord later reproduces the identical sequence, so a saved
## amount at index i in snapshot_state's output always lines back up with
## the regenerated instance at that same index.
var _resource_nodes: Array = []
## Set the moment _maybe_spawn_chest actually creates one (left null if the
## roll said no) -- lets snapshot_state tell "never had a chest here" apart
## from "had one, but it's since been looted" (Chest.open() queue_frees it,
## so is_instance_valid(_chest) goes false).
var _chest: Node = null
## True if this chunk placed a Village (friendly or enemy). ChunkManager
## reads this to permanently exclude this coord from ever being unloaded --
## see this file's own header and ChunkManager's for why neither Village
## kind is designed to survive being torn down and regenerated from scratch.
var has_village: bool = false

## Passed in by ChunkManager on a reload (see snapshot_state) -- {} on a
## genuine first-time generation. Consumed by _maybe_spawn_chest (to
## suppress recreating an already-looted chest) and by
## _apply_saved_resource_amounts (called at the end of generate()).
var _saved_state: Dictionary = {}


## Builds this chunk's ground and scenery. `coord` seeds this chunk's own
## _rng, so this always reproduces the same content for the same `coord`
## (see _rng's own header) -- `saved_state` (from a previous
## snapshot_state(), or {} on a genuine first visit) then patches in
## whatever has actually changed since (harvested amounts, a looted chest).
## Must be called after this node is already positioned in the tree
## (global_position must be final) since ground-height/river/lake sampling
## all read world-space positions for seamless continuity across chunk
## borders.
func generate(coord: Vector2i, p_biome: Biomes.Biome, saved_state: Dictionary = {}) -> void:
	chunk_coord = coord
	biome = p_biome
	_rng.seed = hash(coord)
	_saved_state = saved_state
	_build_ground()
	_scatter_resources()
	_scatter_props()
	_spawn_ambient_particles()
	if _rng.randf() < ANIMAL_CHANCE:
		var count := _rng.randi_range(1, 3)
		for i in count:
			_spawn_one(ANIMAL_SCENE)
	if _rng.randf() < CHEST_CHANCE:
		_maybe_spawn_chest()
	if _rng.randf() < VILLAGE_CHANCE:
		_maybe_spawn_village()
	if _rng.randf() < SLOT_MACHINE_CHANCE:
		_maybe_spawn_slot_machine()
	_apply_saved_resource_amounts()

## Captures this chunk's current mutable state right before ChunkManager
## frees it: every still-tracked resource node's remaining amount (0 for one
## that's fully depleted/mid-respawn), and whether its Chest -- if any --
## has already been looted. A later regeneration of this same coord (see
## generate/restore_state above) re-applies this so the player picks back up
## where they left off instead of everything looking suspiciously freshly
## full/unlooted again.
func snapshot_state() -> Dictionary:
	var amounts: Array = []
	amounts.resize(_resource_nodes.size())
	for i in _resource_nodes.size():
		var node = _resource_nodes[i]
		amounts[i] = node.amount if is_instance_valid(node) else 0
	return {
		"resource_amounts": amounts,
		"chest_looted": _chest != null and not is_instance_valid(_chest),
	}

## Re-applies snapshot_state's saved resource amounts (see _saved_state) to
## this chunk's freshly (re)generated resource nodes -- called once at the
## end of generate(), after every resource/animal instance already exists.
## The chest side of _saved_state is instead consumed directly inside
## _maybe_spawn_chest, before it ever instantiates one, so a looted chest
## never even briefly flashes back into existence.
func _apply_saved_resource_amounts() -> void:
	var amounts: Array = _saved_state.get("resource_amounts", [])
	for i in mini(amounts.size(), _resource_nodes.size()):
		var node = _resource_nodes[i]
		if is_instance_valid(node):
			node.restore_state(amounts[i])

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
## with `Biomes.blended_ground_color_at(...)` -- a continuously-blended
## biome color (see that function's own header on why this needs to be a
## per-*vertex* value rather than baked into the chunk's own tiled
## procedural texture: a texture repeats within one chunk and so can never
## carry a whole-chunk-spanning gradient, while vertex colors interpolate
## smoothly and agree exactly with a neighboring chunk's own mesh at their
## shared border, since both sample the same continuous world-space
## function). Water's own tint/shore/wave data used to also ride on this
## same per-vertex color (multiplied in here) but that aliased badly at the
## water's edge (see feature request: "coastlines... unorganic squared
## coast") -- it's baked into a separate, much finer non-tiling texture
## instead now (see WATER_MASK_SIZE/_build_ground_material), sampled
## per-pixel by ground.gdshader directly from this same mesh's local VERTEX
## position rather than through vertex color, so this function no longer
## needs to touch water at all. Purely cosmetic terrain relief/color --
## Blob/Enemy's global_position.y stays force-clamped to 0.0 every physics
## frame regardless (see CLAUDE.md: "this project has no vertical
## gameplay"), so this never has to agree with unit footing, just look
## pleasant from the RTS camera angle.
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
		colors[i] = Biomes.blended_ground_color_at(world_x, world_z)
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

## Resolution of the water tint/shore/wave-depth bake below -- far coarser
## than TEXTURE_SIZE (this data doesn't need per-texel grain, just enough
## resolution that the water/land edge doesn't visibly facet), but still
## roughly 6x finer per world unit than the old per-vertex approach (one
## sample every 2.5 world units at SUBDIVISIONS=10) that used to alias badly
## at the water's edge (see feature request: "coastlines... unorganic
## squared coast"). Sampled by ground.gdshader directly from this mesh's own
## local VERTEX.xz (unaffected by the chunk node's own world transform, so
## it lines up exactly with the world-space positions this loop samples)
## rather than through the uv_scale-tiled UV the grain texture uses, so one
## texture maps exactly once onto one chunk instead of repeating.
const WATER_MASK_SIZE := 64

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

	# Water tint/shore-foam/wave-depth masks (Biomes.water_sample_at, which
	# already internally combines river/lake into one consistent result --
	# see that function's own header) baked at WATER_MASK_SIZE resolution
	# instead of per-vertex (see that const's own header) -- each texel
	# samples the exact same world-space function the old vertex loop did,
	# just at far finer spacing, so the coastline reads as smooth instead of
	# following the mesh's own coarse vertex grid. One water_sample_at call
	# per texel (rather than the three separate Biomes calls this used to
	# make) also means river/lake noise is only sampled once here instead of
	# three times.
	var water_tint_img := Image.create(WATER_MASK_SIZE, WATER_MASK_SIZE, false, Image.FORMAT_RGB8)
	var water_wave_img := Image.create(WATER_MASK_SIZE, WATER_MASK_SIZE, false, Image.FORMAT_RGB8)
	for wy in WATER_MASK_SIZE:
		var local_z: float = (float(wy) / float(WATER_MASK_SIZE - 1) - 0.5) * CHUNK_SIZE
		for wx in WATER_MASK_SIZE:
			var local_x: float = (float(wx) / float(WATER_MASK_SIZE - 1) - 0.5) * CHUNK_SIZE
			var world_x := global_position.x + local_x
			var world_z := global_position.z + local_z
			# Lava/oil (Biomes.hazard_sample_at) are a fully separate system
			# from real water (see that function's own header) -- wherever a
			# hazard is actually present at this pixel, it simply overrides
			# water's own sample outright rather than blending with it, since
			# the two are gated to essentially disjoint regions anyway (a
			# volcanic hotspot or hot/dry desert climate, vs. wherever
			# river_noise/lake_noise happen to place real water).
			var sample: Dictionary = Biomes.water_sample_at(world_x, world_z)
			var hazard: Dictionary = Biomes.hazard_sample_at(world_x, world_z)
			if hazard.shore > 0.001 or hazard.depth > 0.001:
				sample = hazard
			water_tint_img.set_pixel(wx, wy, sample.tint)
			water_wave_img.set_pixel(wx, wy, Color(sample.shore, sample.depth, sample.get("glow", 0.0)))
	var water_tint_tex := ImageTexture.create_from_image(water_tint_img)
	var water_wave_tex := ImageTexture.create_from_image(water_wave_img)

	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("albedo_texture", tex)
	mat.set_shader_parameter("normal_texture", normal_tex)
	mat.set_shader_parameter("water_tint_texture", water_tint_tex)
	mat.set_shader_parameter("water_wave_texture", water_wave_tex)
	mat.set_shader_parameter("uv_scale", Vector2(4.0, 4.0))
	mat.set_shader_parameter("chunk_size", CHUNK_SIZE)
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
		if _rng.randf() > RESOURCE_ATTEMPT_CHANCE * abundance:
			continue
		var count := maxi(1, roundi(_rng.randi_range(RESOURCE_CLUSTER_COUNT_RANGE.x, RESOURCE_CLUSTER_COUNT_RANGE.y) * abundance))
		for i in count:
			var local := Vector3(_rng.randf_range(-half, half), 0.0, _rng.randf_range(-half, half))
			# A tree/rock/ore floating in a river or lake reads as a clear
			# placement bug (see feature request: "resources cannot be
			# placed on water") -- skipped rather than retried, same
			# no-retry convention _maybe_spawn_chest/_maybe_spawn_village
			# already use, so a biome bordering a lot of water just ends up
			# with a slightly thinner cluster instead of resampling forever.
			if Biomes.is_any_liquid_at(global_position.x + local.x, global_position.z + local.z):
				continue
			var inst: Node3D = entry.scene.instantiate()
			add_child(inst)
			inst.position = local
			inst.rotation.y = _rng.randf() * TAU
			var s := _rng.randf_range(0.85, 1.25)
			inst.scale = Vector3(s, s, s)
			_resource_nodes.append(inst)

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

## Spawns one instance of `scene` at a random point within this chunk --
## tracked in _resource_nodes since the only caller (the animal huddle in
## generate()) instantiates a ResourceNode subclass (Animal).
func _spawn_one(scene: PackedScene) -> void:
	var half := CHUNK_SIZE * 0.5 * (1.0 - RESOURCE_SPAWN_MARGIN)
	var inst: Node3D = scene.instantiate()
	add_child(inst)
	inst.position = Vector3(_rng.randf_range(-half, half), 0.0, _rng.randf_range(-half, half))
	_resource_nodes.append(inst)

## Spawns one Chest at a random point in this chunk (see CHEST_CHANCE) --
## skipped entirely if the rolled spot happens to land on water, rather
## than a chest floating in a lake (no retry, unlike _maybe_spawn_water's
## several attempts -- a chest simply not appearing in this particular
## chunk is a fine outcome given how rare it already is). Also skipped if
## _saved_state says this coord's chest was already looted before this
## chunk was last unloaded -- otherwise reloading would hand the player a
## second, identical free haul.
func _maybe_spawn_chest() -> void:
	if _saved_state.get("chest_looted", false):
		return
	var half := CHUNK_SIZE * 0.5 * (1.0 - RESOURCE_SPAWN_MARGIN)
	var local := Vector3(_rng.randf_range(-half, half), 0.0, _rng.randf_range(-half, half))
	if Biomes.is_any_liquid_at(global_position.x + local.x, global_position.z + local.z):
		return
	var inst: Node3D = CHEST_SCENE.instantiate()
	add_child(inst)
	inst.position = local
	inst.rotation.y = _rng.randf() * TAU
	_chest = inst

## Spawns one Village at a random point in this chunk (see VILLAGE_CHANCE),
## an even coin flip between friendly and enemy -- skipped entirely if the
## rolled spot lands on water, same no-retry convention as
## _maybe_spawn_chest. Sets has_village so ChunkManager permanently excludes
## this coord from ever being unloaded (see this file's own header).
func _maybe_spawn_village() -> void:
	var half := CHUNK_SIZE * 0.5 * (1.0 - RESOURCE_SPAWN_MARGIN)
	var local := Vector3(_rng.randf_range(-half, half), 0.0, _rng.randf_range(-half, half))
	if Biomes.is_any_liquid_at(global_position.x + local.x, global_position.z + local.z):
		return
	var scene: PackedScene = FRIENDLY_VILLAGE_SCENE if _rng.randf() < 0.5 else ENEMY_VILLAGE_SCENE
	var inst: Node3D = scene.instantiate()
	add_child(inst)
	inst.position = local
	inst.rotation.y = _rng.randf() * TAU
	has_village = true

## Spawns one SlotMachine at a random point in this chunk (see
## SLOT_MACHINE_CHANCE) -- skipped entirely if the rolled spot lands on
## water, same no-retry convention as _maybe_spawn_chest/_maybe_spawn_village.
## Never needs anything from _saved_state: a SlotMachine carries no
## persistent state of its own (see its own header -- freely repeatable, no
## "used up" flag), so a regenerated one behaves identically to the one that
## was there before.
func _maybe_spawn_slot_machine() -> void:
	var half := CHUNK_SIZE * 0.5 * (1.0 - RESOURCE_SPAWN_MARGIN)
	var local := Vector3(_rng.randf_range(-half, half), 0.0, _rng.randf_range(-half, half))
	if Biomes.is_any_liquid_at(global_position.x + local.x, global_position.z + local.z):
		return
	var inst: Node3D = SLOT_MACHINE_SCENE.instantiate()
	add_child(inst)
	inst.position = local
	inst.rotation.y = _rng.randf() * TAU
