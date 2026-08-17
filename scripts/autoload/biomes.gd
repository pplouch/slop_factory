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
	## Scales the fine per-vertex height_noise layer only (see height_at) --
	## keep deltas between biomes modest. A chunk is assigned one fixed
	## biome for its whole area, so at a border between two differently-
	## biomed chunks the same shared height_noise value gets multiplied by
	## two different amplitudes on either side, producing a real geometric
	## seam (not just a color-tint difference) the size of that delta. The
	## macro_height_noise layer (biome-independent, always continuous) is
	## what should carry big, obviously-organic elevation changes instead.
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
## A second, much-lower-frequency field summed on top of height_noise for
## broad, multi-chunk valleys/mountains -- height_noise alone only shapes
## relief within roughly one chunk's width, so every chunk of a given biome
## ended up an equally-bumpy repeat of the last rather than the landscape
## rising into a mountain range or sinking into a valley over a stretch of
## many chunks. Biome-independent (unlike height_noise, it isn't scaled by
## Biome.height_amplitude) so a mountain ridge reads as one continuous
## landform even where it happens to cross a biome boundary.
var macro_height_noise := FastNoiseLite.new()
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
## Deep water is a strict subset of "any water" at a stricter threshold/
## narrower band, always leaving a shallow ring/edge between deep water and
## dry land -- see is_deep_water_at. Units can wade the shallow border (to
## gather or build a Water Extractor) but not the deep core; margins picked
## so the shallow band reads as clearly present without swallowing the
## whole feature (a river's central 40% is deep vs. its outer 60% shallow;
## a lake's threshold is nudged up by DEEP_LAKE_MARGIN so a meaningful ring
## around its edge stays shallow).
const DEEP_RIVER_FRACTION := 0.4
const DEEP_LAKE_MARGIN := 0.08
## Ground-vertex tint colors for water_tint_at's smooth land -> shore ->
## shallow -> deep gradient (see feature backlog: "water ridge should have
## a texture on the borders to make it more realistic") -- a sandy ring
## right at the water's edge, replacing the old hard land/water color cut.
const SHORE_TINT_COLOR := Color(0.82, 0.74, 0.52)
const SHALLOW_WATER_TINT_COLOR := Color(0.2, 0.45, 0.7)
const DEEP_WATER_TINT_COLOR := Color(0.08, 0.2, 0.4)
## How wide (in noise-value units, same scale as RIVER_HALF_WIDTH/
## LAKE_THRESHOLD) the sandy shore band is on the land side of the water
## line.
const RIVER_SHORE_BAND := 0.01
const LAKE_SHORE_BAND := 0.03
## Nothing counts as water this close to the origin, so founder blobs never
## spawn standing in a lake.
const WATER_SAFE_RADIUS := 12.0
## How far rivers/lakes sink the ground mesh, purely cosmetic (ground
## collision stays flat regardless, per project convention). Bumped up
## alongside the new macro_height_noise layer below so a river/lake still
## reads as clearly recessed against the now much larger overall terrain
## relief range, instead of looking like it's merely dipped a token amount.
const WATER_BASIN_DEPTH := 1.0
## Amplitude of the broad macro_height_noise layer -- deliberately larger
## than any single biome's height_amplitude so multi-chunk mountains/valleys
## read as the dominant landform, with each biome's own height_amplitude
## adding smaller-scale local texture on top (see height_at).
const MACRO_HEIGHT_AMPLITUDE := 2.4


func _ready() -> void:
	height_noise.seed = 1000
	height_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	height_noise.frequency = 0.05
	height_noise.fractal_octaves = 4
	height_noise.fractal_lacunarity = 2.0
	height_noise.fractal_gain = 0.5

	macro_height_noise.seed = 1500
	macro_height_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	macro_height_noise.frequency = 0.006
	macro_height_noise.fractal_octaves = 3
	macro_height_noise.fractal_lacunarity = 2.0
	macro_height_noise.fractal_gain = 0.5

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

	_register(Biome.new("plains", "Plains", Color(0.29, 0.56, 0.24), 0.4,
		[{"scene": TREE_SCENE, "resource_type": "wood"}, {"scene": ROCK_SCENE, "resource_type": "stone"}],
		["slime"]
	))
	_register(Biome.new("forest", "Forest", Color(0.16, 0.42, 0.2), 0.6,
		[{"scene": TREE_SCENE, "resource_type": "wood"}, {"scene": MUSHROOM_SCENE, "resource_type": "mushroom"}],
		["wolf", "spider"]
	))
	_register(Biome.new("desert", "Desert", Color(0.76, 0.68, 0.42), 0.7,
		[{"scene": ROCK_SCENE, "resource_type": "stone"}, {"scene": CACTUS_SCENE, "resource_type": "cactus_fiber"}],
		["scorpion", "bandit"]
	))
	_register(Biome.new("tundra", "Tundra", Color(0.82, 0.87, 0.92), 0.5,
		[{"scene": ROCK_SCENE, "resource_type": "stone"}, {"scene": ICE_CRYSTAL_SCENE, "resource_type": "ice_crystal"}],
		["yeti", "wolf"]
	))
	_register(Biome.new("swamp", "Swamp", Color(0.24, 0.3, 0.2), 0.35,
		[{"scene": TREE_SCENE, "resource_type": "wood"}, {"scene": MUSHROOM_SCENE, "resource_type": "mushroom"}],
		["leech", "spider"]
	))
	_register(Biome.new("jungle", "Jungle", Color(0.11, 0.48, 0.16), 0.6,
		[{"scene": TREE_SCENE, "resource_type": "wood"}, {"scene": MUSHROOM_SCENE, "resource_type": "mushroom"}],
		["panther", "wolf"]
	))
	_register(Biome.new("volcanic", "Volcanic", Color(0.28, 0.14, 0.12), 0.9,
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

## This biome's terrain height at `world_x`/`world_z`: a broad, biome-
## independent macro_height_noise layer (multi-chunk valleys/mountains) plus
## this biome's own finer height_noise layer (local unevenness, scaled by
## Biome.height_amplitude so e.g. Volcanic reads craggier than Plains),
## sunk into a basin if the position also falls in a river or lake (see
## is_water_at). Both noise fields are shared/world-space-sampled, so any
## two chunks sampling the same world position always agree, unlike the old
## per-chunk-seeded noise.
func height_at(world_x: float, world_z: float, biome: Biome) -> float:
	var height: float = macro_height_noise.get_noise_2d(world_x, world_z) * MACRO_HEIGHT_AMPLITUDE
	height += height_noise.get_noise_2d(world_x, world_z) * biome.height_amplitude
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

## Whether `world_x`/`world_z` is *deep* water specifically -- a stricter
## subset of is_water_at (see DEEP_RIVER_FRACTION/DEEP_LAKE_MARGIN above)
## that PathingManager blocks units from entering, unlike the shallow
## border ring around it. Always implies is_water_at is also true, since
## both thresholds here are strictly tighter than the plain water ones.
func is_deep_water_at(world_x: float, world_z: float) -> bool:
	if Vector2(world_x, world_z).length() < WATER_SAFE_RADIUS:
		return false
	if absf(river_noise.get_noise_2d(world_x, world_z)) < RIVER_HALF_WIDTH * DEEP_RIVER_FRACTION:
		return true
	return lake_noise.get_noise_2d(world_x, world_z) > LAKE_THRESHOLD + DEEP_LAKE_MARGIN

## Ground-vertex tint for `world_x`/`world_z`: white (no tint) on dry land,
## smoothly blending through a sandy `SHORE_TINT_COLOR` ring as the
## underlying river/lake noise approaches its water threshold, then through
## `SHALLOW_WATER_TINT_COLOR` to `DEEP_WATER_TINT_COLOR` past it -- replaces
## the old hard is_water_at binary cut with a continuous gradient read from
## the same noise fields is_river_at/is_lake_at/is_deep_water_at already
## classify booleans from, so the visual boundary always agrees with the
## gameplay one (Chunk used to tint every water vertex the same flat color;
## used by Chunk._build_ground_mesh for its vertex colors).
func water_tint_at(world_x: float, world_z: float) -> Color:
	if Vector2(world_x, world_z).length() < WATER_SAFE_RADIUS:
		return Color.WHITE

	var river_n := absf(river_noise.get_noise_2d(world_x, world_z))
	if river_n < RIVER_HALF_WIDTH + RIVER_SHORE_BAND:
		if river_n >= RIVER_HALF_WIDTH:
			var shore_t: float = smoothstep(RIVER_HALF_WIDTH + RIVER_SHORE_BAND, RIVER_HALF_WIDTH, river_n)
			return Color.WHITE.lerp(SHORE_TINT_COLOR, shore_t)
		var deep_t: float = smoothstep(RIVER_HALF_WIDTH * DEEP_RIVER_FRACTION, 0.0, river_n)
		return SHALLOW_WATER_TINT_COLOR.lerp(DEEP_WATER_TINT_COLOR, deep_t)

	var lake_n := lake_noise.get_noise_2d(world_x, world_z)
	if lake_n > LAKE_THRESHOLD - LAKE_SHORE_BAND:
		if lake_n < LAKE_THRESHOLD:
			var shore_t: float = smoothstep(LAKE_THRESHOLD - LAKE_SHORE_BAND, LAKE_THRESHOLD, lake_n)
			return Color.WHITE.lerp(SHORE_TINT_COLOR, shore_t)
		var deep_t: float = smoothstep(LAKE_THRESHOLD, LAKE_THRESHOLD + DEEP_LAKE_MARGIN, lake_n)
		return SHALLOW_WATER_TINT_COLOR.lerp(DEEP_WATER_TINT_COLOR, deep_t)

	return Color.WHITE

## Whether `world_x`/`world_z` is a rare volcanic hotspot, checked before
## the temperature/humidity climate grid.
func is_volcanic_at(world_x: float, world_z: float) -> bool:
	return volcanic_noise.get_noise_2d(world_x, world_z) > VOLCANIC_THRESHOLD
