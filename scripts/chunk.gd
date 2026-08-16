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
const SUBDIVISIONS := 6
const HEIGHT_NOISE_FREQUENCY := 0.08
const TEXTURE_SIZE := 32
const TEXTURE_NOISE_FREQUENCY := 0.18

## Resource clusters attempted per chunk (each biome resource entry has an
## independent chance to actually appear, so not every chunk gets one of
## everything its biome offers).
const RESOURCE_ATTEMPT_CHANCE := 0.7
const RESOURCE_CLUSTER_COUNT_RANGE := Vector2i(2, 5)
const RESOURCE_SPAWN_MARGIN := 0.4  # fraction of CHUNK_SIZE kept clear of the very edge

## Chance this chunk also gets a small huddle of Animals (food source).
const ANIMAL_CHANCE := 0.35
const ANIMAL_SCENE: PackedScene = preload("res://scenes/animal.tscn")

## Chance this chunk gets a water pond (a little more common near plains).
const WATER_CHANCE := 0.12
const WATER_SCENE: PackedScene = preload("res://scenes/water_pond.tscn")

var biome: Biomes.Biome
var chunk_coord: Vector2i


## Builds this chunk's ground and scenery. `coord` is used only to seed
## per-chunk randomness deterministically (not strictly required since
## chunks never regenerate, but keeps a given coordinate's *shape*
## reproducible if ever needed for debugging). Must be called after this
## node is already positioned in the tree (global_position must be final)
## since ground-height noise is sampled in world space for seamless
## continuity across chunk borders.
func generate(coord: Vector2i, p_biome: Biomes.Biome) -> void:
	chunk_coord = coord
	biome = p_biome
	_build_ground()
	_scatter_resources()
	if randf() < WATER_CHANCE:
		_spawn_one(WATER_SCENE)
	if randf() < ANIMAL_CHANCE:
		var count := randi_range(1, 3)
		for i in count:
			_spawn_one(ANIMAL_SCENE)

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
## UVs) and displaces only its vertices' Y, so the height variation is
## purely cosmetic terrain relief -- Blob/Enemy's global_position.y stays
## force-clamped to 0.0 every physics frame regardless (see CLAUDE.md:
## "this project has no vertical gameplay"), so this never has to agree
## with unit footing, just look pleasant from the RTS camera angle.
func _build_ground_mesh() -> ArrayMesh:
	var plane := PlaneMesh.new()
	plane.size = Vector2(CHUNK_SIZE, CHUNK_SIZE)
	plane.subdivide_width = SUBDIVISIONS
	plane.subdivide_depth = SUBDIVISIONS

	var arrays: Array = plane.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]

	var noise := FastNoiseLite.new()
	noise.seed = hash(chunk_coord)
	noise.frequency = HEIGHT_NOISE_FREQUENCY

	for i in vertices.size():
		var v := vertices[i]
		var world_x := global_position.x + v.x
		var world_z := global_position.z + v.z
		var height: float = noise.get_noise_2d(world_x, world_z) * biome.height_amplitude
		vertices[i] = Vector3(v.x, height, v.z)
	arrays[Mesh.ARRAY_VERTEX] = vertices

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
## reads as textured terrain rather than a flat color swatch.
func _build_ground_material() -> StandardMaterial3D:
	var img := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGB8)
	var tex_noise := FastNoiseLite.new()
	tex_noise.seed = hash(chunk_coord) + 1
	tex_noise.frequency = TEXTURE_NOISE_FREQUENCY
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

## Spawns one instance of `scene` at a random point within this chunk.
func _spawn_one(scene: PackedScene) -> void:
	var half := CHUNK_SIZE * 0.5 * (1.0 - RESOURCE_SPAWN_MARGIN)
	var inst: Node3D = scene.instantiate()
	add_child(inst)
	inst.position = Vector3(randf_range(-half, half), 0.0, randf_range(-half, half))
