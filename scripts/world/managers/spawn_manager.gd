class_name SpawnManager
extends RefCounted
## Owns the player's starting crew and the ambient enemy population -- split
## out of world.gd (see CLAUDE.md's "world.gd -- the central controller"
## section). A plain RefCounted; World's own _ready calls the founder/initial-
## population methods once, and owns the recurring population-check Timer
## (Timer needs to live in the scene tree, so World still hosts it and just
## calls back into `maintain_enemy_population()`).

const ENEMY_SCENE: PackedScene = preload("res://scenes/units/enemy/enemy.tscn")
const BLOB_SCENE: PackedScene = preload("res://scenes/units/blob/blob.tscn")

# There's no building at game start -- the player has to construct the Town
# Hall themselves via Build Mode. These few blobs exist so there's something
# to select and command before that happens, spawned directly by World
# rather than by any Building.
const FOUNDER_BLOB_COUNT := 3
const FOUNDER_SPAWN_RADIUS := 2.0

# A lone ambient threat, maintained at a small target count rather than
# growing unbounded: a background check tops the population back up a while
# after something dies, similar to how resource nodes respawn. Each spawn
# picks a random *already-loaded* chunk and an enemy kind from that chunk's
# biome (see Biomes), so kind and difficulty stay biome-appropriate.
const ENEMY_TARGET_COUNT := 3
const ENEMY_POPULATION_CHECK_INTERVAL := 20.0

var _world: Node3D
var _chunk_manager: ChunkManager


func setup(world: Node3D, chunk_manager: ChunkManager) -> void:
	_world = world
	_chunk_manager = chunk_manager

## Spawns the player's starting crew directly (not via any Building, since
## none exists yet) at the map origin, evenly spaced in a small ring.
func spawn_founder_blobs() -> void:
	for i in FOUNDER_BLOB_COUNT:
		var angle := (TAU / FOUNDER_BLOB_COUNT) * i
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * FOUNDER_SPAWN_RADIUS
		var blob: Node3D = BLOB_SCENE.instantiate()
		blob.kind_id = "worker"
		_world.add_child(blob)
		blob.global_position = offset
		blob.play_spawn_pop()

## Spawns one enemy at a random point within a random already-loaded chunk,
## picking one of that chunk's biome's enemy kinds (see Biomes/EnemyKinds) so
## both difficulty and flavor stay appropriate to where it lands -- a chunk
## near the origin is always "plains" (slime only), so the immediate
## starting area never spawns the tougher outer-biome kinds.
func spawn_one_enemy() -> void:
	if _chunk_manager.loaded_chunks.is_empty():
		return
	var chunk: Chunk = _chunk_manager.loaded_chunks.values().pick_random()
	var kind_id: String = chunk.biome.enemy_kind_ids.pick_random()
	var half := Chunk.CHUNK_SIZE * 0.5
	var enemy: Node3D = ENEMY_SCENE.instantiate()
	enemy.kind_id = kind_id
	_world.add_child(enemy)
	enemy.global_position = chunk.global_position + Vector3(randf_range(-half, half), 0.0, randf_range(-half, half))

## Signal handler for the population-check timer: tops the enemy count back
## up to ENEMY_TARGET_COUNT one at a time (rather than all at once) if
## anything has died since the last check.
func maintain_enemy_population() -> void:
	if _world.get_tree().get_nodes_in_group("enemies").size() < ENEMY_TARGET_COUNT:
		spawn_one_enemy()
