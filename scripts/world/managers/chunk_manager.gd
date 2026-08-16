class_name ChunkManager
extends RefCounted
## Minecraft-style "generate as the camera approaches" world tiling, split out
## of world.gd (see CLAUDE.md's "world.gd -- the central controller" section
## for why). See scripts/world/chunk.gd for what a chunk actually builds.
##
## A plain RefCounted, not a Node -- it holds no engine callbacks of its own;
## World's own _process calls `process()` below every frame, since chunk
## streaming needs to react to the camera's current position, which only
## World (the actual scene node) can read.

const CHUNK_LOAD_RADIUS := 3
const CHUNK_CHECK_INTERVAL := 0.5

## Chunk coordinate (Vector2i) -> the generated Chunk node there. Read
## externally by SpawnManager (picks a random already-loaded chunk to spawn
## an enemy in) -- deliberately public (no leading underscore) for that.
var loaded_chunks: Dictionary = {}

var _world: Node3D
var _check_timer := 0.0


func setup(world: Node3D) -> void:
	_world = world

## Called from World._process every frame; only actually re-checks chunk
## coverage every CHUNK_CHECK_INTERVAL seconds, not every single frame.
func process(delta: float, focus_position: Vector3) -> void:
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = CHUNK_CHECK_INTERVAL
		ensure_chunks_loaded(focus_position)

## Generates every chunk within CHUNK_LOAD_RADIUS of `around_world_pos` that
## isn't already loaded. Cheap to call repeatedly -- a no-op dictionary
## lookup for every chunk that already exists, real generation work only
## for genuinely new ones.
func ensure_chunks_loaded(around_world_pos: Vector3) -> void:
	var center_coord := _world_pos_to_chunk_coord(around_world_pos)
	for dy in range(-CHUNK_LOAD_RADIUS, CHUNK_LOAD_RADIUS + 1):
		for dx in range(-CHUNK_LOAD_RADIUS, CHUNK_LOAD_RADIUS + 1):
			var coord := center_coord + Vector2i(dx, dy)
			if not loaded_chunks.has(coord):
				_generate_chunk(coord)

## World-space position -> the chunk coordinate containing it.
func _world_pos_to_chunk_coord(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / Chunk.CHUNK_SIZE), floori(pos.z / Chunk.CHUNK_SIZE))

## Chunk coordinate -> the world-space position of its center.
func _chunk_center_world(coord: Vector2i) -> Vector3:
	return Vector3((coord.x + 0.5) * Chunk.CHUNK_SIZE, 0.0, (coord.y + 0.5) * Chunk.CHUNK_SIZE)

## Instantiates, positions, and generates the chunk at `coord`, picking its
## biome from its world-space center (see Biomes.biome_for_world_pos).
func _generate_chunk(coord: Vector2i) -> void:
	var center := _chunk_center_world(coord)
	var biome := Biomes.biome_for_world_pos(center)
	var chunk := Chunk.new()
	_world.add_child(chunk)
	chunk.position = center
	chunk.generate(coord, biome)
	loaded_chunks[coord] = chunk
