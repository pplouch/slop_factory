extends Node
## Biomes (Registry pattern, autoload). Each biome defines what a chunk in
## its territory looks like (ground tint) and what it can contain: 2-3
## resource-node scenes (some shared with other biomes, at least one usually
## unique -- 5 of the 7 biomes also get their own ore, see IRON_ORE_SCENE
## etc. below) and 1-3 enemy kinds (see EnemyKinds) that don't spawn
## anywhere else. Chunk asks `biome_for_world_pos` to decide a new chunk's
## biome, then reads this data to populate it.
##
## This is also the single shared source for every world-generation noise
## field (temperature/humidity/volcanic-hotspot biome classification, river/
## lake placement): every FastNoiseLite here uses a fixed seed and is
## queried in *world* space, so any two chunks sampling the same world
## position -- regardless of which one generates first -- always get the
## same answer. Ground terrain used to also carry a multi-layer height/
## relief system (macro_height_noise plus a per-biome height_noise layer),
## removed since it was purely cosmetic (this project has no vertical
## gameplay -- Blob/Enemy's global_position.y stays force-clamped to 0.0
## regardless, see height_at's own note) and, from this project's steep
## top-down camera, subtle enough not to earn its own upkeep (see feature
## backlog: "remove height on the map as it is not well used"). The water
## basin dip (see WATER_BASIN_DEPTH/height_at) stayed -- unlike the general
## relief, it's a small, legible cue paired directly with the water-tint
## gradient, not the "not well used" system this removal targeted.

class Biome:
	var id: String
	var display_name: String
	var ground_color: Color
	## Array of {scene: PackedScene, resource_type: String} -- resource
	## nodes this biome scatters. Kept as scene+type pairs (not just a
	## scene) since resource_node.gd's `resource_type`/`max_amount` are
	## already @export-driven per instance.
	var resources: Array
	var enemy_kind_ids: Array

	func _init(p_id: String, p_name: String, p_color: Color,
			p_resources: Array, p_enemy_kind_ids: Array) -> void:
		id = p_id
		display_name = p_name
		ground_color = p_color
		resources = p_resources
		enemy_kind_ids = p_enemy_kind_ids

const TREE_SCENE: PackedScene = preload("res://scenes/world_objects/tree.tscn")
const ROCK_SCENE: PackedScene = preload("res://scenes/world_objects/rock.tscn")
const MUSHROOM_SCENE: PackedScene = preload("res://scenes/world_objects/mushroom.tscn")
const CACTUS_SCENE: PackedScene = preload("res://scenes/world_objects/cactus.tscn")
const ICE_CRYSTAL_SCENE: PackedScene = preload("res://scenes/world_objects/ice_crystal.tscn")
const OBSIDIAN_SCENE: PackedScene = preload("res://scenes/world_objects/obsidian_shard.tscn")
# Ores (see feature backlog 2: "Add more resources... which are ores"),
# one per biome below, each processed by Foundry into its matching bar --
# see scripts/buildings/foundry.gd.
const IRON_ORE_SCENE: PackedScene = preload("res://scenes/world_objects/iron_ore.tscn")
const GOLD_ORE_SCENE: PackedScene = preload("res://scenes/world_objects/gold_ore.tscn")
const SILVER_ORE_SCENE: PackedScene = preload("res://scenes/world_objects/silver_ore.tscn")
const PLATINUM_ORE_SCENE: PackedScene = preload("res://scenes/world_objects/platinum_ore.tscn")
const SLOPIUM_ORE_SCENE: PackedScene = preload("res://scenes/world_objects/slopium_ore.tscn")

## Radius (world units) of the always-plains starting area around the
## origin, where founder blobs spawn and the player builds first -- kept
## free of the harsher outer biomes' tougher enemies and of any river/lake
## (see is_water_at) so the player never starts standing in water. Widened
## (see feature backlog: "biomes should be farther away and take more
## space, so their unique resources are harder to get from the beginning")
## alongside temperature_noise/humidity_noise's own lowered frequency below,
## which enlarges every biome region beyond this radius too -- between the
## two, reaching any biome-exclusive resource now takes meaningfully more
## exploration than before.
const PLAINS_RADIUS := 90.0

var _biomes: Dictionary = {}
var _ordered_ids: Array = []

## -- Shared world-generation noise fields --
## Biome-classification fields, all low frequency since a biome region
## should span many chunks, not fluctuate chunk to chunk -- halved from
## this project's earlier values (0.004/0.0045) so each region is roughly
## twice as wide (see PLAINS_RADIUS's own note).
var temperature_noise := FastNoiseLite.new()
var humidity_noise := FastNoiseLite.new()
## Rare hotspots (thresholded, see is_volcanic_at) checked before the
## temperature/humidity grid -- volcanic activity doesn't follow climate.
var volcanic_noise := FastNoiseLite.new()
## Broad, slow-varying field blended into difficulty_at alongside raw
## distance from the origin -- see that function's own header for why a
## noise layer is mixed in rather than using pure distance alone.
var difficulty_noise := FastNoiseLite.new()
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
## collision stays flat regardless, per project convention) -- the one
## piece of terrain relief kept after removing the general macro/per-biome
## height system (see this file's own header), since it's a small, legible
## cue paired directly with water_tint_at's gradient rather than the
## "not well used" system that removal targeted.
const WATER_BASIN_DEPTH := 1.0

## -- Smooth biome-color blending (see feature request: "the transition
## between biomes is brutal, doesn't feel organic") -- Chunk/resource/enemy
## population still use the coarse, single-biome-per-chunk classification
## above (biome_for_world_pos); blending *which* resources/enemies spawn
## continuously would be a much bigger change than what was actually
## reported, a purely visual complaint about ground color snapping at a
## chunk's hard edge. blended_ground_color_at instead gives the ground's
## own color a continuous, softened version of the exact same
## classification tree, so it eases across a boundary over a real physical
## distance instead of snapping the instant one chunk's single center-point
## sample crosses a threshold.
const BIOME_BLEND_BAND := 0.06
const PLAINS_BLEND_BAND := 12.0
const VOLCANIC_BLEND_BAND := 0.08

## -- Difficulty-by-distance noise layer (see feature request: "the farther
## the biome is, the rarer the resources and the harder the enemies") --
## blends raw distance from the origin with a broad noise field so the
## increase isn't a perfectly circular ring (which would read as
## artificial) while still correlating strongly with "farther = harder".
const DIFFICULTY_MAX_DISTANCE := 1500.0
const MAX_ENEMY_DIFFICULTY_MULT := 2.5
const MIN_RESOURCE_ABUNDANCE_MULT := 0.35


func _ready() -> void:
	temperature_noise.seed = 2000
	temperature_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	temperature_noise.frequency = 0.002

	humidity_noise.seed = 3000
	humidity_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	humidity_noise.frequency = 0.00225

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

	difficulty_noise.seed = 7000
	difficulty_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	difficulty_noise.frequency = 0.0015

	_register(Biome.new("plains", "Plains", Color(0.29, 0.56, 0.24),
		[{"scene": TREE_SCENE, "resource_type": "wood"}, {"scene": ROCK_SCENE, "resource_type": "stone"}, {"scene": IRON_ORE_SCENE, "resource_type": "iron"}],
		["slime"]
	))
	_register(Biome.new("forest", "Forest", Color(0.16, 0.42, 0.2),
		[{"scene": TREE_SCENE, "resource_type": "wood"}, {"scene": MUSHROOM_SCENE, "resource_type": "mushroom"}],
		["wolf", "spider"]
	))
	_register(Biome.new("desert", "Desert", Color(0.76, 0.68, 0.42),
		[{"scene": ROCK_SCENE, "resource_type": "stone"}, {"scene": CACTUS_SCENE, "resource_type": "cactus_fiber"}, {"scene": GOLD_ORE_SCENE, "resource_type": "gold"}],
		["scorpion", "bandit"]
	))
	_register(Biome.new("tundra", "Tundra", Color(0.82, 0.87, 0.92),
		[{"scene": ROCK_SCENE, "resource_type": "stone"}, {"scene": ICE_CRYSTAL_SCENE, "resource_type": "ice_crystal"}, {"scene": SILVER_ORE_SCENE, "resource_type": "silver"}],
		["yeti", "wolf"]
	))
	_register(Biome.new("swamp", "Swamp", Color(0.24, 0.3, 0.2),
		[{"scene": TREE_SCENE, "resource_type": "wood"}, {"scene": MUSHROOM_SCENE, "resource_type": "mushroom"}, {"scene": SLOPIUM_ORE_SCENE, "resource_type": "slopium"}],
		["leech", "spider"]
	))
	_register(Biome.new("jungle", "Jungle", Color(0.11, 0.48, 0.16),
		[{"scene": TREE_SCENE, "resource_type": "wood"}, {"scene": MUSHROOM_SCENE, "resource_type": "mushroom"}],
		["panther", "wolf"]
	))
	_register(Biome.new("volcanic", "Volcanic", Color(0.28, 0.14, 0.12),
		[{"scene": ROCK_SCENE, "resource_type": "stone"}, {"scene": OBSIDIAN_SCENE, "resource_type": "obsidian"}, {"scene": PLATINUM_ORE_SCENE, "resource_type": "platinum"}],
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

## Terrain height at `world_x`/`world_z` -- flat (0.0) everywhere except a
## basin sink where the position falls in a river or lake (see is_water_at).
## The general per-biome terrain relief this used to also compute was
## removed as purely cosmetic and not worth its upkeep (see this file's own
## header); the water basin dip stayed as the one deliberate exception.
func height_at(world_x: float, world_z: float) -> float:
	return -WATER_BASIN_DEPTH if is_water_at(world_x, world_z) else 0.0

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

## Smoothly-blended ground color at `world_x`/`world_z` -- see this file's
## own header on BIOME_BLEND_BAND for why this exists alongside the hard
## biome_for_world_pos classification rather than replacing it. Read
## per-vertex by Chunk._build_ground_mesh: vertex colors interpolate
## smoothly across a mesh (and agree exactly at a shared border with a
## neighboring chunk's own mesh, since both sample this same continuous
## function), unlike a chunk's own procedural texture, which tiles *within*
## one chunk and so can never carry a whole-chunk-spanning gradient.
func blended_ground_color_at(world_x: float, world_z: float) -> Color:
	var dist := Vector2(world_x, world_z).length()
	var temperature := _remap(temperature_noise.get_noise_2d(world_x, world_z))
	var humidity := _remap(humidity_noise.get_noise_2d(world_x, world_z))
	var climate_color := _climate_blend_color(temperature, humidity)

	var volcanic_n := volcanic_noise.get_noise_2d(world_x, world_z)
	var volcanic_w: float = smoothstep(VOLCANIC_THRESHOLD - VOLCANIC_BLEND_BAND, VOLCANIC_THRESHOLD + VOLCANIC_BLEND_BAND, volcanic_n)
	var outer_color: Color = climate_color.lerp(get_biome("volcanic").ground_color, volcanic_w)

	var plains_w: float = 1.0 - smoothstep(PLAINS_RADIUS - PLAINS_BLEND_BAND, PLAINS_RADIUS + PLAINS_BLEND_BAND, dist)
	return outer_color.lerp(get_biome("plains").ground_color, plains_w)

## Softened mirror of biome_for_world_pos's climate if/elif tree -- each
## weight construction follows the exact same hierarchy (temperature
## decides cold/mid/hot first, humidity only splits *within* whichever
## temperature band), so this always resolves to the same dominant color
## biome_for_world_pos would pick well away from any threshold, and only
## actually blends between neighbors within BIOME_BLEND_BAND of one.
func _climate_blend_color(temperature: float, humidity: float) -> Color:
	var cold_w: float = 1.0 - smoothstep(TEMPERATURE_COLD - BIOME_BLEND_BAND, TEMPERATURE_COLD + BIOME_BLEND_BAND, temperature)
	var hot_w: float = smoothstep(TEMPERATURE_HOT - BIOME_BLEND_BAND, TEMPERATURE_HOT + BIOME_BLEND_BAND, temperature)
	var mid_w: float = clamp(1.0 - cold_w - hot_w, 0.0, 1.0)

	var jungle_in_hot: float = smoothstep(0.5 - BIOME_BLEND_BAND, 0.5 + BIOME_BLEND_BAND, humidity)
	var desert_in_hot: float = 1.0 - jungle_in_hot

	var wet_m: float = smoothstep(HUMIDITY_WET - BIOME_BLEND_BAND, HUMIDITY_WET + BIOME_BLEND_BAND, humidity)
	var dry_m: float = 1.0 - smoothstep(HUMIDITY_DRY - BIOME_BLEND_BAND, HUMIDITY_DRY + BIOME_BLEND_BAND, humidity)
	var swamp_m: float = clamp(1.0 - wet_m - dry_m, 0.0, 1.0)
	var mid_h_total: float = wet_m + dry_m + swamp_m
	if mid_h_total > 0.0:
		wet_m /= mid_h_total
		dry_m /= mid_h_total
		swamp_m /= mid_h_total

	var color := Color(0.0, 0.0, 0.0)
	color += get_biome("tundra").ground_color * cold_w
	color += get_biome("jungle").ground_color * (hot_w * jungle_in_hot)
	color += get_biome("desert").ground_color * (hot_w * desert_in_hot)
	color += get_biome("forest").ground_color * (mid_w * wet_m)
	color += get_biome("plains").ground_color * (mid_w * dry_m)
	color += get_biome("swamp").ground_color * (mid_w * swamp_m)
	return color

## 0..1 "how dangerous/scarce should this position be" -- mostly driven by
## raw distance from the origin, with a broad noise field blended in so
## equal-distance points aren't perfectly identical (a pure radial ring
## would read as artificial the same way a hard biome-classification edge
## did, see blended_ground_color_at's own header for the same reasoning
## applied to ground color). Saturates at 1.0 past DIFFICULTY_MAX_DISTANCE.
func difficulty_at(world_x: float, world_z: float) -> float:
	var dist := Vector2(world_x, world_z).length()
	var dist_factor: float = clamp(dist / DIFFICULTY_MAX_DISTANCE, 0.0, 1.0)
	var noise_factor: float = _remap(difficulty_noise.get_noise_2d(world_x, world_z))
	return clamp(dist_factor * 0.7 + noise_factor * 0.3, 0.0, 1.0)

## Multiplier Enemy should apply on top of GameManager's own time-based
## ramp (see GameManager.get_enemy_difficulty_multiplier) -- the two stack
## multiplicatively (time makes the whole map harder as a session goes on;
## this makes any single moment's difficulty vary by how far out an enemy
## actually spawned). 1.0 near the origin, rising to MAX_ENEMY_DIFFICULTY_MULT
## at DIFFICULTY_MAX_DISTANCE and beyond.
func enemy_difficulty_multiplier_at(world_x: float, world_z: float) -> float:
	return lerp(1.0, MAX_ENEMY_DIFFICULTY_MULT, difficulty_at(world_x, world_z))

## Multiplier Chunk._scatter_resources should apply to its own
## RESOURCE_ATTEMPT_CHANCE/cluster counts -- 1.0 near the origin, dropping
## to MIN_RESOURCE_ABUNDANCE_MULT at DIFFICULTY_MAX_DISTANCE and beyond, so
## resources read as progressively scarcer the farther out a chunk is.
func resource_abundance_multiplier_at(world_x: float, world_z: float) -> float:
	return lerp(1.0, MIN_RESOURCE_ABUNDANCE_MULT, difficulty_at(world_x, world_z))

## 0..1 shoreline-foam intensity at `world_x`/`world_z`, peaking exactly at
## the river/lake noise threshold water_tint_at itself blends across (a
## river's RIVER_HALF_WIDTH crossing, a lake's LAKE_THRESHOLD) and fading to
## 0 within one shore-band's width to either side -- reuses those same
## thresholds/bands rather than new tuning constants, so the animated foam
## in scripts/world/ground.gdshader always lines up with the existing
## sandy-shore/shallow-water tint band instead of drifting from it. Baked
## into ground-mesh vertex-color alpha by Chunk (see
## Chunk._build_ground_mesh), since the shader itself has no noise access.
func shore_factor_at(world_x: float, world_z: float) -> float:
	if Vector2(world_x, world_z).length() < WATER_SAFE_RADIUS:
		return 0.0

	var river_n := absf(river_noise.get_noise_2d(world_x, world_z))
	if river_n < RIVER_HALF_WIDTH + RIVER_SHORE_BAND:
		return clamp(1.0 - absf(river_n - RIVER_HALF_WIDTH) / RIVER_SHORE_BAND, 0.0, 1.0)

	var lake_n := lake_noise.get_noise_2d(world_x, world_z)
	if lake_n > LAKE_THRESHOLD - LAKE_SHORE_BAND:
		return clamp(1.0 - absf(lake_n - LAKE_THRESHOLD) / LAKE_SHORE_BAND, 0.0, 1.0)

	return 0.0
