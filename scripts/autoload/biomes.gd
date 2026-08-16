extends Node
## Biomes (Registry pattern, autoload). Each biome defines what a chunk in
## its territory looks like (ground tint + terrain relief amplitude) and
## what it can contain: 1-2 resource-node scenes (some shared with other
## biomes, at least one usually unique) and 1-3 enemy kinds (see
## EnemyKinds) that don't spawn anywhere else. Chunk asks
## `biome_for_world_pos` to decide a new chunk's biome, then reads this
## data to populate it.
##
## This is also the single shared source for every world-generation noise
## field (terrain height, temperature/humidity/volcanic-hotspot biome
## classification, river/lake placement): every FastNoiseLite here uses a
## fixed seed and is queried in *world* space, so any two chunks sampling
## the same world position -- regardless of which one generates first --
## always get the same answer. Chunk used to create its own per-chunk-
## seeded height noise, which is exactly why terrain height used to be
## incoherent across chunk borders (the same border vertex got a different
## height depending on which side generated it first); giving every chunk
## the same noise fields instead of a fresh one each fixes that.

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

const TREE_SCENE: PackedScene = preload("res://scenes/world_objects/tree.tscn")
const ROCK_SCENE: PackedScene = preload("res://scenes/world_objects/rock.tscn")
const MUSHROOM_SCENE: PackedScene = preload("res://scenes/world_objects/mushroom.tscn")
const CACTUS_SCENE: PackedScene = preload("res://scenes/world_objects/cactus.tscn")
const ICE_CRYSTAL_SCENE: PackedScene = preload("res://scenes/world_objects/ice_crystal.tscn")
const OBSIDIAN_SCENE: PackedScene = preload("res://scenes/world_objects/obsidian_shard.tscn")

## Radius (world units) of the always-plains starting area around the
## origin, where founder blobs spawn and the player builds first -- kept
## free of the harsher outer biomes' tougher enemies and of any river/lake
## (see is_water_at) so the player never starts standing in water.
const PLAINS_RADIUS := 32.0

var _biomes: Dictionary = {}
var _ordered_ids: Array = []

## -- Shared world-generation noise fields --
## Terrain relief: low frequency with several fractal octaves layered on
## top of each other (Perlin, per-octave amplitude halving/frequency
## doubling -- FastNoiseLite's built-in fractal support does exactly this
## "multiple noise layers summed together" for us) so the ground reads as
## naturally uneven at more than one scale instead of one smooth wave.
var height_noise := FastNoiseLite.new()
## Biome-classification fields, all much lower frequency than height_noise
## since a biome region should span many chunks, not fluctuate chunk to
## chunk.
var temperature_noise := FastNoiseLite.new()
var humidity_noise := FastNoiseLite.new()
## Rare hotspots (thresholded, see is_volcanic_at) checked before the
## temperature/humidity grid -- volcanic activity doesn't follow climate.
var volcanic_noise := FastNoiseLite.new()
## Rivers: winding line-like features wherever this noise crosses zero
## (see is_river_at) -- a classic "ridged" trick that needs no pathing/
## graph-connectivity work and is naturally continuous across chunks since
## it's one shared field sampled in world space.
var river_noise := FastNoiseLite.new()
## Lakes: broad, slow-varying blobs wherever this noise exceeds a
## threshold (see is_lake_at).
var lake_noise := FastNoiseLite.new()

const TEMPERATURE_COLD := 0.35
const TEMPERATURE_HOT := 0.65
const HUMIDITY_WET := 0.6
const HUMIDITY_DRY := 0.35
## Both empirically calibrated against single-octave Perlin's actual
## practical range (it rarely approaches the theoretical +/-1 extremes) --
## 0.4/0.35 land at roughly the top 1-3% of sampled values, so volcanic
## hotspots/lakes read as a genuinely occasional feature rather than either
## vanishingly rare or covering large stretches of the map.
const VOLCANIC_THRESHOLD := 0.4
const RIVER_HALF_WIDTH := 0.035
const LAKE_THRESHOLD := 0.35
## Nothing counts as water this close to the origin, so founder blobs never
## spawn standing in a lake.
const WATER_SAFE_RADIUS := 12.0
## How far rivers/lakes sink the ground mesh, purely cosmetic (ground
## collision stays flat regardless, per project convention).
const WATER_BASIN_DEPTH := 0.6


func _ready() -> void:
	height_noise.seed = 1000
	height_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	height_noise.frequency = 0.05
	height_noise.fractal_octaves = 4
	height_noise.fractal_lacunarity = 2.0
	height_noise.fractal_gain = 0.5

	temperature_noise.seed = 2000
	temperature_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	temperature_noise.frequency = 0.004

	humidity_noise.seed = 3000
	humidity_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	humidity_noise.frequency = 0.0045

	volcanic_noise.seed = 4000
	volcanic_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	volcanic_noise.frequency = 0.01

	river_noise.seed = 5000
	river_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	river_noise.frequency = 0.015
	river_noise.fractal_octaves = 2

	lake_noise.seed = 6000
	lake_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	lake_noise.frequency = 0.006

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
	_register(Biome.new("tundra", "Tundra", Color(0.82, 0.87, 0.92), 0.22,
		[{"scene": ROCK_SCENE, "resource_type": "stone"}, {"scene": ICE_CRYSTAL_SCENE, "resource_type": "ice_crystal"}],
		["yeti", "wolf"]
	))
	_register(Biome.new("swamp", "Swamp", Color(0.24, 0.3, 0.2), 0.12,
		[{"scene": TREE_SCENE, "resource_type": "wood"}, {"scene": MUSHROOM_SCENE, "resource_type": "mushroom"}],
		["leech", "spider"]
	))
	_register(Biome.new("jungle", "Jungle", Color(0.11, 0.48, 0.16), 0.32,
		[{"scene": TREE_SCENE, "resource_type": "wood"}, {"scene": MUSHROOM_SCENE, "resource_type": "mushroom"}],
		["panther", "wolf"]
	))
	_register(Biome.new("volcanic", "Volcanic", Color(0.28, 0.14, 0.12), 0.5,
		[{"scene": ROCK_SCENE, "resource_type": "stone"}, {"scene": OBSIDIAN_SCENE, "resource_type": "obsidian"}],
		["imp", "scorpion"]
	))

func _register(biome: Biome) -> void:
	_biomes[biome.id] = biome
	_ordered_ids.append(biome.id)

func get_biome(id: String) -> Biome:
	return _biomes.get(id, _biomes.get("plains"))

func get_ordered_ids() -> Array:
	return _ordered_ids

## Deterministically picks which biome the chunk centered on `world_pos`
## belongs to: an inner plains circle around the origin (the safe starting
## area) is unchanged, but everything outside it is now placed procedurally
## from temperature/humidity noise (a classic 3-band-by-2-band climate
## grid) with volcanic hotspots layered on top, checked first, since real
## volcanic activity doesn't follow a climate band the way the other 6 do.
func biome_for_world_pos(world_pos: Vector3) -> Biome:
	var dist := Vector2(world_pos.x, world_pos.z).length()
	if dist < PLAINS_RADIUS:
		return get_biome("plains")

	if is_volcanic_at(world_pos.x, world_pos.z):
		return get_biome("volcanic")

	var temperature := _remap(temperature_noise.get_noise_2d(world_pos.x, world_pos.z))
	var humidity := _remap(humidity_noise.get_noise_2d(world_pos.x, world_pos.z))

	if temperature < TEMPERATURE_COLD:
		return get_biome("tundra")
	if temperature > TEMPERATURE_HOT:
		return get_biome("jungle") if humidity > 0.5 else get_biome("desert")

	if humidity > HUMIDITY_WET:
		return get_biome("forest")
	if humidity < HUMIDITY_DRY:
		return get_biome("plains")
	return get_biome("swamp")

## Remaps a FastNoiseLite sample (roughly -1..1) into 0..1.
func _remap(n: float) -> float:
	return clamp((n + 1.0) * 0.5, 0.0, 1.0)

## This biome's terrain height at `world_x`/`world_z`, sunk into a basin if
## the position also falls in a river or lake (see is_water_at) -- the
## single shared height_noise field means any two chunks sampling the same
## world position always agree, unlike the old per-chunk-seeded noise.
func height_at(world_x: float, world_z: float, biome: Biome) -> float:
	var height: float = height_noise.get_noise_2d(world_x, world_z) * biome.height_amplitude
	if is_water_at(world_x, world_z):
		height -= WATER_BASIN_DEPTH
	return height

## Whether `world_x`/`world_z` falls within a river's winding path -- a
## thin band around wherever river_noise crosses zero, the standard
## "ridged noise" trick for line-like features with no pathing/graph work.
func is_river_at(world_x: float, world_z: float) -> bool:
	if Vector2(world_x, world_z).length() < WATER_SAFE_RADIUS:
		return false
	return absf(river_noise.get_noise_2d(world_x, world_z)) < RIVER_HALF_WIDTH

## Whether `world_x`/`world_z` falls within a lake -- a broad region where
## the (much lower-frequency) lake_noise field exceeds a threshold.
func is_lake_at(world_x: float, world_z: float) -> bool:
	if Vector2(world_x, world_z).length() < WATER_SAFE_RADIUS:
		return false
	return lake_noise.get_noise_2d(world_x, world_z) > LAKE_THRESHOLD

## Whether `world_x`/`world_z` is any kind of water (river or lake) -- used
## by height_at/Chunk's ground-vertex coloring, which don't care which.
func is_water_at(world_x: float, world_z: float) -> bool:
	return is_river_at(world_x, world_z) or is_lake_at(world_x, world_z)

## Whether `world_x`/`world_z` is a rare volcanic hotspot, checked before
## the temperature/humidity climate grid.
func is_volcanic_at(world_x: float, world_z: float) -> bool:
	return volcanic_noise.get_noise_2d(world_x, world_z) > VOLCANIC_THRESHOLD
