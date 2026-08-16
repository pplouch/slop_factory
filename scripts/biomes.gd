extends Node
## Biomes (Registry pattern, autoload). Each biome defines what a chunk in
## its territory looks like (ground tint + terrain relief amplitude) and
## what it can contain: 1-2 resource-node scenes (some shared with other
## biomes, at least one usually unique) and 1-3 enemy kinds (see
## EnemyKinds) that don't spawn anywhere else. ChunkManager asks
## `biome_for_world_pos` to decide a new chunk's biome, then reads this
## data to populate it.

class Biome:
	var id: String
	var display_name: String
	var ground_color: Color
	var height_amplitude: float
	## Array of {scene: PackedScene, resource_type: String} -- resource
	## nodes this biome scatters. Kept as scene+type pairs (not just a
	## scene) since resource_node.gd's `resource_type`/`max_amount` are
	## already @export-driven per instance.
	var resources: Array
	var enemy_kind_ids: Array

	func _init(p_id: String, p_name: String, p_color: Color, p_amplitude: float,
			p_resources: Array, p_enemy_kind_ids: Array) -> void:
		id = p_id
		display_name = p_name
		ground_color = p_color
		height_amplitude = p_amplitude
		resources = p_resources
		enemy_kind_ids = p_enemy_kind_ids

const TREE_SCENE: PackedScene = preload("res://scenes/tree.tscn")
const ROCK_SCENE: PackedScene = preload("res://scenes/rock.tscn")
const MUSHROOM_SCENE: PackedScene = preload("res://scenes/mushroom.tscn")
const CACTUS_SCENE: PackedScene = preload("res://scenes/cactus.tscn")

## Radius (world units) of the always-plains starting area around the
## origin, where founder blobs spawn and the player builds first -- kept
## free of the harsher outer biomes' tougher enemies.
const PLAINS_RADIUS := 32.0

var _biomes: Dictionary = {}
var _ordered_ids: Array = []


func _ready() -> void:
	_register(Biome.new("plains", "Plains", Color(0.29, 0.56, 0.24), 0.15,
		[{"scene": TREE_SCENE, "resource_type": "wood"}, {"scene": ROCK_SCENE, "resource_type": "stone"}],
		["slime"]
	))
	_register(Biome.new("forest", "Forest", Color(0.16, 0.42, 0.2), 0.3,
		[{"scene": TREE_SCENE, "resource_type": "wood"}, {"scene": MUSHROOM_SCENE, "resource_type": "mushroom"}],
		["wolf", "spider"]
	))
	_register(Biome.new("desert", "Desert", Color(0.76, 0.68, 0.42), 0.4,
		[{"scene": ROCK_SCENE, "resource_type": "stone"}, {"scene": CACTUS_SCENE, "resource_type": "cactus_fiber"}],
		["scorpion", "bandit"]
	))

func _register(biome: Biome) -> void:
	_biomes[biome.id] = biome
	_ordered_ids.append(biome.id)

func get_biome(id: String) -> Biome:
	return _biomes.get(id, _biomes.get("plains"))

func get_ordered_ids() -> Array:
	return _ordered_ids

## Deterministically picks which biome a chunk centered on `world_pos`
## belongs to: an inner plains circle around the origin (the safe starting
## area), split into a forest half and a desert half beyond that --
## simple angle/distance rules rather than real noise-based blending, which
## keeps biome borders predictable and cheap to query per-chunk.
func biome_for_world_pos(world_pos: Vector3) -> Biome:
	var dist := Vector2(world_pos.x, world_pos.z).length()
	if dist < PLAINS_RADIUS:
		return get_biome("plains")
	var angle := atan2(world_pos.z, world_pos.x)
	if angle >= 0.0:
		return get_biome("forest")
	return get_biome("desert")
