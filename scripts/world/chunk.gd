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
## Doubled from the original 32 (see feature backlog: "smooth and improve
## terrain texture") -- TEXTURE_NOISE_FREQUENCY was halved alongside it so
## the mottling pattern keeps the same physical size per chunk, just
## resolved at twice the pixel density (less blocky/pixelated up close).
const TEXTURE_SIZE := 64
const TEXTURE_NOISE_FREQUENCY := 0.09

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

## Rivers/lakes are placed procedurally (see Biomes.is_river_at/is_lake_at)
## rather than at a flat per-chunk chance -- a chunk only gets a harvestable
## water source if one of a few sampled points inside it actually lands on
## river/lake terrain, so water reads as following the same winding
## rivers/broad lakes the ground tinting shows instead of scattering
## puddles anywhere.
const WATER_PLACEMENT_ATTEMPTS := 6
const RIVER_POND_SCENE: PackedScene = preload("res://scenes/world_objects/water_pond.tscn")
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
## via Biomes.water_tint_at -- white on dry land, smoothly blending through
## a sandy shore ring and into shallow/deep water as the underlying noise
## approaches and passes its water threshold (see feature backlog: "water
## ridge should have a texture on the borders to make it more realistic").
## Both are purely cosmetic terrain relief/color -- Blob/Enemy's
## global_position.y stays force-clamped to 0.0 every physics frame
## regardless (see CLAUDE.md: "this project has no vertical gameplay"), so
## this never has to agree with unit footing, just look pleasant from the
## RTS camera angle.
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
		colors[i] = Biomes.water_tint_at(world_x, world_z)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors

	var base_mesh := ArrayMesh.new()
	base_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	base_mesh.surface_set_material(0, _build_ground_material())

	var st := SurfaceTool.new()
	st.create_from(base_mesh, 0)
	st.generate_normals()
	return st.commit()

## Builds a small procedurally-mottled texture tinted to this biome's
## ground_color (light/dark noise bands, the same "generate an Image by
## hand" technique BeltSegment uses for its stripe texture) so the ground
## reads as textured terrain rather than a flat color swatch. Vertex colors
## (see _build_ground_mesh) multiply on top of this via
## vertex_color_use_as_albedo, tinting river/lake vertices blue without
## needing a second, position-sampled texture.
func _build_ground_material() -> StandardMaterial3D:
	var img := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGB8)
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
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var n: float = (tex_noise.get_noise_2d(x, y) + 1.0) * 0.5
			var shade: Color = biome.ground_color.darkened(0.12).lerp(biome.ground_color.lightened(0.12), n)
			img.set_pixel(x, y, shade)
	var tex := ImageTexture.create_from_image(img)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.95
	mat.uv1_scale = Vector3(4.0, 4.0, 1.0)
	mat.vertex_color_use_as_albedo = true
	return mat

## Scatters a handful of small resource clusters using this chunk's
## biome's resource list (see Biomes.Biome.resources) -- each resource
## entry independently has RESOURCE_ATTEMPT_CHANCE of appearing at all in
## this particular chunk, so neighboring chunks of the same biome still
## look varied rather than identically populated.
func _scatter_resources() -> void:
	var half := CHUNK_SIZE * 0.5 * (1.0 - RESOURCE_SPAWN_MARGIN)
	for entry in biome.resources:
		if randf() > RESOURCE_ATTEMPT_CHANCE:
			continue
		var count := randi_range(RESOURCE_CLUSTER_COUNT_RANGE.x, RESOURCE_CLUSTER_COUNT_RANGE.y)
		for i in count:
			var inst: Node3D = entry.scene.instantiate()
			add_child(inst)
			inst.position = Vector3(randf_range(-half, half), 0.0, randf_range(-half, half))
			inst.rotation.y = randf() * TAU
			var s := randf_range(0.85, 1.25)
			inst.scale = Vector3(s, s, s)

## Tries a few random points within this chunk (see WATER_PLACEMENT_ATTEMPTS)
## and, the first time one actually lands on lake or river terrain (see
## Biomes.is_lake_at/is_river_at), spawns a matching harvestable water
## source there -- a big Lake for a lake hit, a smaller pond for a river
## crossing. Most chunks sample none and get no water at all, since rivers/
## lakes are now a localized procedural feature rather than a flat chance
## anywhere.
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
		if Biomes.is_river_at(world_x, world_z):
			var inst: Node3D = RIVER_POND_SCENE.instantiate()
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
