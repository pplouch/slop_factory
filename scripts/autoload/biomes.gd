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
## field (temperature/humidity/volcanic-hotspot biome classification, lake/
## lava/oil placement): every FastNoiseLite here uses a fixed seed and is
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
##
## Real water is lakes only (see feature request: "remove the water rivers,
## they are not natural enough") -- a real water river (river_noise, a
## ridged noise band) was tried and removed: even after domain-warping it
## (see _warp below), a thin winding line feature never stopped reading as a
## noise artifact the way a broad lake's threshold blob does. Lava keeps its
## own river feature (lava_river_noise) since that specific complaint was
## about *water* rivers, not lava's.
##
## _warp offsets the *sampling position* fed into lake_noise (and every
## hazard-liquid noise field below) by a second, independent, much-lower-
## frequency pair of fields (warp_x_noise/warp_z_noise), the standard
## "domain warp" technique: a raw single-frequency thresholded field reads as
## an obviously synthetic, same-size evenly-spaced blob lattice, since it
## repeats identically everywhere. Warping the position first breaks that
## regularity without a more exotic noise algorithm, since the warp field
## itself doesn't repeat in sync with whatever it's warping -- no two lake
## shapes end up looking quite the same.
##
## Lakes, lava, and oil are mutually exclusive by construction (see feature
## request: "lakes and rivers and oil and lava SHOULD NOT overlap") rather
## than merely unlikely to coincide: the map is partitioned into three
## disjoint zones using the exact same conditions the biome classification
## itself already uses (so this doubles as free biome coherence, see feature
## request: "stay coherent with the biomes") --
## 1. `is_volcanic_at` true -> the Lava zone. Only lava (is_lava_at, lake-
##    style pools merged with river-style streams) can appear here; real
##    water (is_lake_at) and oil (is_oil_at) both explicitly exclude this
##    zone regardless of what their own noise fields say.
## 2. Not volcanic, but `_is_hot_dry_climate_at` true (the same condition the
##    Desert branch of biome_for_world_pos checks) -> the Oil zone. Only oil
##    can appear here; real water excludes this zone too.
## 3. Neither -> the Water zone. Only real water (lakes) can appear here --
##    lava/oil's own gates above already can't be true in this zone, so no
##    extra exclusion is needed on their end.
## Each zone's own boolean gate lives in that liquid's is_xxx_at function
## (is_lake_at/is_lava_at/is_oil_at/is_deep_water_at/is_deep_oil_at), so every
## caller -- PathingManager, Chunk's scatter avoidance, hazard_sample_at,
## water_sample_at -- sees the same partition automatically; nothing computes
## its own separate "which zone am I in" logic.
##
## Deliberately not new Biome registry entries for lava/oil: both are
## localized terrain features layered onto an existing biome's territory, the
## same relationship lakes already have with every biome, not a whole new
## chunk-spanning climate region.

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
## free of the harsher outer biomes' tougher enemies and of any lake
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
## Lakes: broad, slow-varying blobs wherever this noise exceeds a
## threshold (see is_lake_at) -- real water's only remaining feature (see
## this file's own header on why the old ridged-noise river was removed).
var lake_noise := FastNoiseLite.new()
## Domain-warp fields (see this file's own header) -- deliberately two
## independent fields at slightly different frequencies rather than one
## reused for both axes, so the warp itself isn't symmetric/diagonal.
var warp_x_noise := FastNoiseLite.new()
var warp_z_noise := FastNoiseLite.new()
## Lava: lake-style pools plus river-style streams, both gated on
## is_volcanic_at (see this file's own header on why).
var lava_lake_noise := FastNoiseLite.new()
var lava_river_noise := FastNoiseLite.new()
## Oil: lake-style pools only (no rivers, per the feature request's own
## wording), gated on _is_hot_dry_climate_at (see this file's own header).
var oil_lake_noise := FastNoiseLite.new()

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
const LAKE_THRESHOLD := 0.35
## Deep water is a strict subset of "any water" at a stricter threshold,
## always leaving a shallow ring/edge between deep water and dry land -- see
## is_deep_water_at. Units can wade the shallow border (to gather or build a
## Water Extractor) but not the deep core; the lake's own threshold is
## nudged up by DEEP_LAKE_MARGIN so a meaningful ring around its edge stays
## shallow instead of the whole feature reading as deep at once.
const DEEP_LAKE_MARGIN := 0.08
## Ground-vertex tint colors for water_tint_at's smooth land -> shore ->
## shallow -> deep gradient (see feature backlog: "water ridge should have
## a texture on the borders to make it more realistic") -- a sandy ring
## right at the water's edge, replacing the old hard land/water color cut.
const SHORE_TINT_COLOR := Color(0.82, 0.74, 0.52)
const SHALLOW_WATER_TINT_COLOR := Color(0.2, 0.45, 0.7)
const DEEP_WATER_TINT_COLOR := Color(0.08, 0.2, 0.4)
## How wide (in noise-value units, same scale as LAKE_THRESHOLD) the sandy
## shore band is on the land side of the water line.
const LAKE_SHORE_BAND := 0.03
## Nothing counts as water this close to the origin, so founder blobs never
## spawn standing in a lake.
const WATER_SAFE_RADIUS := 12.0
## How far lakes/lava/oil sink the ground mesh, purely cosmetic (ground
## collision stays flat regardless, per project convention) -- the one
## piece of terrain relief kept after removing the general macro/per-biome
## height system (see this file's own header), since it's a small, legible
## cue paired directly with water_tint_at's gradient rather than the
## "not well used" system that removal targeted.
const WATER_BASIN_DEPTH := 1.0
## World-unit amplitude of the domain warp applied before every lake/lava/
## oil noise lookup (see this file's own header and _warp). Large enough
## relative to each feature's own noise frequency to meaningfully reshape a
## lake's edge, not so large it disconnects the warped sample from the
## surrounding unwarped world (ground color, biome classification, etc. all
## stay unwarped).
const WATER_WARP_AMPLITUDE := 45.0

## -- Lava (volcanic-only hazard liquid, see this file's own header) --
const LAVA_LAKE_THRESHOLD := 0.45
const LAVA_LAKE_DEEP_MARGIN := 0.1
const LAVA_RIVER_HALF_WIDTH := 0.02
const LAVA_RIVER_DEEP_FRACTION := 0.5
const LAVA_SHORE_BAND := 0.02
## Charred-rock shore ring -> molten shallow -> white-hot deep core.
const LAVA_SHORE_TINT_COLOR := Color(0.12, 0.07, 0.05)
const LAVA_SHALLOW_TINT_COLOR := Color(0.9, 0.35, 0.05)
const LAVA_DEEP_TINT_COLOR := Color(0.65, 0.1, 0.02)

## -- Oil (desert-only hazard liquid, see this file's own header) --
const OIL_LAKE_THRESHOLD := 0.5
const OIL_LAKE_DEEP_MARGIN := 0.1
const OIL_SHORE_BAND := 0.025
## Damp dark soil shore ring -> near-black slick -> deeper near-black core
## (oil doesn't get a dramatically different shallow/deep split the way
## lava's molten-to-white-hot core does -- real crude oil just reads as
## uniformly dark, so these two are deliberately close to each other).
const OIL_SHORE_TINT_COLOR := Color(0.16, 0.13, 0.09)
const OIL_SHALLOW_TINT_COLOR := Color(0.08, 0.06, 0.05)
const OIL_DEEP_TINT_COLOR := Color(0.015, 0.012, 0.01)

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

	lake_noise.seed = 6000
	lake_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	lake_noise.frequency = 0.006
	# Explicitly configured (rather than relying on FastNoiseLite's own
	# default fractal settings) so a lake's threshold contour picks up real
	# edge irregularity -- inlets/points instead of a smooth blob outline --
	# regardless of what the engine's defaults happen to be.
	lake_noise.fractal_octaves = 4
	lake_noise.fractal_lacunarity = 2.0
	lake_noise.fractal_gain = 0.45

	warp_x_noise.seed = 8000
	warp_x_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	warp_x_noise.frequency = 0.004
	warp_x_noise.fractal_octaves = 2

	warp_z_noise.seed = 9000
	warp_z_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	# Deliberately different from warp_x_noise's own frequency so the warp
	# isn't perfectly diagonal/symmetric between the two axes.
	warp_z_noise.frequency = 0.0037
	warp_z_noise.fractal_octaves = 2

	lava_lake_noise.seed = 10000
	lava_lake_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	lava_lake_noise.frequency = 0.02
	lava_lake_noise.fractal_octaves = 3

	lava_river_noise.seed = 11000
	lava_river_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	lava_river_noise.frequency = 0.025
	lava_river_noise.fractal_octaves = 3

	oil_lake_noise.seed = 12000
	oil_lake_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	oil_lake_noise.frequency = 0.018
	oil_lake_noise.fractal_octaves = 3

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
## basin sink where the position falls in any liquid feature (real water,
## lava, or oil -- see is_any_liquid_at). The general per-biome terrain
## relief this used to also compute was removed as purely cosmetic and not
## worth its upkeep (see this file's own header); the basin dip stayed as
## the one deliberate exception.
func height_at(world_x: float, world_z: float) -> float:
	return -WATER_BASIN_DEPTH if is_any_liquid_at(world_x, world_z) else 0.0

## Offsets `world_x`/`world_z` by a low-frequency, independent-per-axis warp
## field before it's fed into any lake/lava/oil noise lookup (see this
## file's own header on why) -- everything *else* (biome classification,
## ground color, difficulty) stays sampled at the true, unwarped position.
func _warp(world_x: float, world_z: float) -> Vector2:
	return Vector2(
		world_x + warp_x_noise.get_noise_2d(world_x, world_z) * WATER_WARP_AMPLITUDE,
		world_z + warp_z_noise.get_noise_2d(world_x, world_z) * WATER_WARP_AMPLITUDE
	)

## Whether `world_x`/`world_z` falls within a lake -- a broad region where
## the (much lower-frequency, warped) lake_noise field exceeds a threshold.
## Excludes the Lava and Oil zones outright (see this file's own header on
## the three-way partition) regardless of what lake_noise itself says there,
## so real water can never overlap either hazard liquid.
func is_lake_at(world_x: float, world_z: float) -> bool:
	if Vector2(world_x, world_z).length() < WATER_SAFE_RADIUS:
		return false
	if is_volcanic_at(world_x, world_z) or _is_hot_dry_climate_at(world_x, world_z):
		return false
	var w := _warp(world_x, world_z)
	return lake_noise.get_noise_2d(w.x, w.y) > LAKE_THRESHOLD

## Whether `world_x`/`world_z` is any kind of *real water* -- lakes only (see
## this file's own header on why the old river feature was removed). Used by
## Chunk's ground-vertex water-avoidance scattering and by Water Extractor's
## own placement gating, both of which specifically mean H2O, not the hazard
## liquids below (see is_any_liquid_at for "any liquid at all"). Kept as its
## own named function (rather than every caller just calling is_lake_at
## directly) since "is this real water" reads clearer at each call site than
## "is this a lake" does, and it's one less thing to rename if water ever
## grows a second feature again.
func is_water_at(world_x: float, world_z: float) -> bool:
	return is_lake_at(world_x, world_z)

## Whether `world_x`/`world_z` is *deep* water specifically -- a stricter
## subset of is_water_at (see DEEP_LAKE_MARGIN above) that PathingManager
## blocks units from entering, unlike the shallow border ring around it.
## Always implies is_water_at is also true, since this threshold is strictly
## tighter than the plain water one (and both exclude the same Lava/Oil
## zones is_lake_at does, so the "deep implies shallow" guarantee holds).
func is_deep_water_at(world_x: float, world_z: float) -> bool:
	if Vector2(world_x, world_z).length() < WATER_SAFE_RADIUS:
		return false
	if is_volcanic_at(world_x, world_z) or _is_hot_dry_climate_at(world_x, world_z):
		return false
	var w := _warp(world_x, world_z)
	return lake_noise.get_noise_2d(w.x, w.y) > LAKE_THRESHOLD + DEEP_LAKE_MARGIN

## The exact hot/dry climate condition the Desert branch of
## biome_for_world_pos checks (temperature past TEMPERATURE_HOT, humidity at
## or below the jungle/desert split) -- factored out so oil's own placement
## gate (is_oil_at) reuses precisely the same condition rather than an
## independently-drifting approximation of it (see this file's own header on
## why that's what makes oil "coherent with the biomes" for free).
func _is_hot_dry_climate_at(world_x: float, world_z: float) -> bool:
	var temperature := _remap(temperature_noise.get_noise_2d(world_x, world_z))
	var humidity := _remap(humidity_noise.get_noise_2d(world_x, world_z))
	return temperature > TEMPERATURE_HOT and humidity <= 0.5

## Whether `world_x`/`world_z` is molten lava -- lake-style pools or river-
## style streams, gated on is_volcanic_at (see this file's own header).
## Always impassable at every point where this is true, no separate "deep"
## tier the way water/oil get: real lava has no safe shallow edge to wade.
## Guarded on PLAINS_RADIUS rather than the narrower WATER_SAFE_RADIUS,
## since is_volcanic_at can never be true that close to the origin anyway
## (biome_for_world_pos's own plains override), and lava should never appear
## anywhere the ground doesn't already agree is volcanic.
func is_lava_at(world_x: float, world_z: float) -> bool:
	if Vector2(world_x, world_z).length() < PLAINS_RADIUS:
		return false
	if not is_volcanic_at(world_x, world_z):
		return false
	var w := _warp(world_x, world_z)
	if lava_lake_noise.get_noise_2d(w.x, w.y) > LAVA_LAKE_THRESHOLD:
		return true
	return absf(lava_river_noise.get_noise_2d(w.x, w.y)) < LAVA_RIVER_HALF_WIDTH

## Whether `world_x`/`world_z` is an oil pool -- lake-style only, gated on
## _is_hot_dry_climate_at (see this file's own header). Also explicitly
## excludes the Lava zone (is_volcanic_at) even though a hot/dry desert
## climate and a volcanic hotspot are independent fields that could
## otherwise coincide (a hot volcanic region is a perfectly plausible climate
## combination) -- Lava takes precedence in that case, the same precedence
## hazard_sample_at's own if/elif ordering already gives it, so is_oil_at
## never disagrees with what hazard_sample_at would actually render there.
## Unlike lava, oil does get a shallow wadable border (see is_deep_oil_at)
## the same way real water does.
func is_oil_at(world_x: float, world_z: float) -> bool:
	if Vector2(world_x, world_z).length() < PLAINS_RADIUS:
		return false
	if is_volcanic_at(world_x, world_z) or not _is_hot_dry_climate_at(world_x, world_z):
		return false
	var w := _warp(world_x, world_z)
	return oil_lake_noise.get_noise_2d(w.x, w.y) > OIL_LAKE_THRESHOLD

## Oil's counterpart to is_deep_water_at -- PathingManager blocks units from
## entering this stricter subset of is_oil_at, same shallow-border-stays-
## walkable shape as real water, and the same Lava-zone exclusion is_oil_at
## itself uses.
func is_deep_oil_at(world_x: float, world_z: float) -> bool:
	if Vector2(world_x, world_z).length() < PLAINS_RADIUS:
		return false
	if is_volcanic_at(world_x, world_z) or not _is_hot_dry_climate_at(world_x, world_z):
		return false
	var w := _warp(world_x, world_z)
	return oil_lake_noise.get_noise_2d(w.x, w.y) > OIL_LAKE_THRESHOLD + OIL_LAKE_DEEP_MARGIN

## Whether `world_x`/`world_z` is occupied by *any* liquid feature -- real
## water, lava, or oil -- used everywhere something just needs "don't place
## a tree/chest/building/resource here", which doesn't care which kind of
## liquid it is (unlike is_water_at, still needed on its own for Water
## Extractor's specifically-real-water gating).
func is_any_liquid_at(world_x: float, world_z: float) -> bool:
	return is_water_at(world_x, world_z) or is_lava_at(world_x, world_z) or is_oil_at(world_x, world_z)

## Ground-vertex tint for `world_x`/`world_z`: white (no tint) on dry land,
## smoothly blending through a sandy `SHORE_TINT_COLOR` ring as the
## underlying lake noise approaches its water threshold, then through
## `SHALLOW_WATER_TINT_COLOR` to `DEEP_WATER_TINT_COLOR` past it -- replaces
## the old hard is_water_at binary cut with a continuous gradient read from
## the same noise field is_lake_at/is_deep_water_at already classify booleans
## from, so the visual boundary always agrees with the gameplay one (Chunk
## used to tint every water vertex the same flat color; used by
## Chunk._build_ground_mesh for its vertex colors). Thin wrapper around
## water_sample_at.
func water_tint_at(world_x: float, world_z: float) -> Color:
	var sample: Dictionary = water_sample_at(world_x, world_z)
	return sample.tint

## Real water's tint/shore/depth at `world_x`/`world_z` -- neutral (white/0/0)
## within WATER_SAFE_RADIUS or the Lava/Oil zones (see this file's own header
## on the three-way partition; is_lake_at's own gate is the single source of
## truth this mirrors), otherwise a direct pass-through to _lake_water_sample
## now that real water is lakes only (see this file's own header on why the
## old river feature -- and the river/lake merge this function used to do --
## were both removed).
func water_sample_at(world_x: float, world_z: float) -> Dictionary:
	if Vector2(world_x, world_z).length() < WATER_SAFE_RADIUS:
		return {"tint": Color.WHITE, "shore": 0.0, "depth": 0.0}
	if is_volcanic_at(world_x, world_z) or _is_hot_dry_climate_at(world_x, world_z):
		return {"tint": Color.WHITE, "shore": 0.0, "depth": 0.0}
	return _lake_water_sample(world_x, world_z)

## 0..1(+) "wetness" -> tint, shared identically across every liquid sample
## in this file rather than each one computing its own independently-shaped
## tint curve -- originally the fix for a real bug in the old river/lake
## merge (see feature request: "we can still see the river edges in the
## lake"): even once dominance blends smoothly by whichever source has the
## higher `wetness`, two sources' *tint* values at the crossover point
## (equal wetness) could still disagree substantially if each was calibrated
## against a different scale that happened to share a normalization
## denominator with the *dominance* comparison but not with each other's
## actual color output. Lava's own lake+river merge (_merge_two_liquid_samples)
## is the one place left in this file that still blends two sources this way
## -- routing both through this one shared function means wherever their
## wetness values coincide (exactly the blend crossover condition), their
## tints already agree too, by construction, rather than needing to
## separately verify two independently-tuned curves happen to match.
## SHORE_WETNESS marks "right at the water line" in this shared 0..1(+)
## scale: below it is the sandy/charred shore ring (0 = the shore band's
## outer, driest edge), at/above it is shallow-to-deep (1.0 = the deep
## threshold, continuing to extrapolate past 1 toward a source's own visual
## center for a still-darkening deep tint).
const SHORE_WETNESS := 0.4

func _tint_for_wetness(wetness: float) -> Color:
	return _tint_for_wetness_colored(wetness, SHORE_TINT_COLOR, SHALLOW_WATER_TINT_COLOR, DEEP_WATER_TINT_COLOR)

## Generalized form of _tint_for_wetness, parameterized by which liquid's own
## shore/shallow/deep colors to blend through -- lets lava/oil reuse the
## exact same wetness-driven curve shape with their own color set instead of
## copy-pasting this formula per liquid (see this file's own header on
## "shared helpers vs. inheritance" in CLAUDE.md's own style section: these
## liquids are the same *shape* of feature, not the same kind of thing worth
## a class hierarchy over). _tint_for_wetness itself is kept as a thin
## 1-argument wrapper (fixed to water's own colors) since it's called
## directly, single-argument, by an existing regression test.
func _tint_for_wetness_colored(wetness: float, shore_color: Color, shallow_color: Color, deep_color: Color) -> Color:
	if wetness < SHORE_WETNESS:
		var shore_t: float = smoothstep(0.0, SHORE_WETNESS, wetness)
		return Color.WHITE.lerp(shore_color, shore_t)
	var deep_t: float = smoothstep(SHORE_WETNESS, 1.0, wetness)
	return shallow_color.lerp(deep_color, deep_t)

## Shared "ridged" line-feature sampler (river-style: inside the feature
## wherever |noise| < half_width) -- wetness/shore/depth/tint for a value
## already sampled from *some* noise field at *some* (possibly warped)
## position, parameterized by that field's own half-width/shore-band/deep-
## fraction/color set. Currently only lava_river_noise drives this (real
## water's own river feature was removed, see this file's own header), but
## it's kept general/parameterized rather than inlined into
## _lava_river_sample directly since it shares _tint_for_wetness_colored's
## exact curve shape with _blob_liquid_sample below (see that function's own
## header on why that sharing matters). Well-behaved (neutral tint/shore/
## depth, wetness saturating below 0) everywhere far from the feature, not
## just within half_width + shore_band, since every branch below is already
## a clamped smoothstep/absf ratio.
func _ridge_liquid_sample(n: float, half_width: float, shore_band: float, deep_fraction: float,
		shore_color: Color, shallow_color: Color, deep_color: Color) -> Dictionary:
	var abs_n := absf(n)
	var shore: float = clamp(1.0 - absf(abs_n - half_width) / shore_band, 0.0, 1.0)
	var depth := 0.0
	if abs_n < half_width:
		depth = smoothstep(half_width, half_width * deep_fraction, abs_n)

	var wetness: float
	if abs_n >= half_width:
		# Shore band: 0 at the outer (dry) edge -> SHORE_WETNESS right at
		# the water line.
		var shore_span: float = clamp(1.0 - (abs_n - half_width) / shore_band, 0.0, 1.0)
		wetness = shore_span * SHORE_WETNESS
	else:
		# Interior: SHORE_WETNESS at the water line -> 1.0 at the deep
		# threshold, extrapolating past 1.0 toward the feature's own center
		# (n == 0) for a tint that keeps darkening slightly past the
		# gameplay deep cutoff.
		var deep_span: float = half_width - half_width * deep_fraction
		var deep_progress: float = (half_width - abs_n) / deep_span
		wetness = SHORE_WETNESS + deep_progress * (1.0 - SHORE_WETNESS)

	return {"tint": _tint_for_wetness_colored(wetness, shore_color, shallow_color, deep_color), "shore": shore, "depth": depth, "wetness": wetness}

## Shared "blob" threshold-feature sampler (lake-style: inside the feature
## wherever noise > threshold) -- lake_noise/lava_lake_noise/oil_lake_noise's
## shared counterpart to _ridge_liquid_sample, see that function's own header.
func _blob_liquid_sample(n: float, threshold: float, shore_band: float, deep_margin: float,
		shore_color: Color, shallow_color: Color, deep_color: Color) -> Dictionary:
	var shore: float = clamp(1.0 - absf(n - threshold) / shore_band, 0.0, 1.0)
	var depth := 0.0
	if n > threshold:
		depth = smoothstep(threshold, threshold + deep_margin, n)

	var wetness: float
	if n <= threshold:
		var shore_span: float = clamp(1.0 - (threshold - n) / shore_band, 0.0, 1.0)
		wetness = shore_span * SHORE_WETNESS
	else:
		var deep_progress: float = (n - threshold) / deep_margin
		wetness = SHORE_WETNESS + deep_progress * (1.0 - SHORE_WETNESS)

	return {"tint": _tint_for_wetness_colored(wetness, shore_color, shallow_color, deep_color), "shore": shore, "depth": depth, "wetness": wetness}

## Real water's (lake) tint/shore/depth/wetness at `world_x`/`world_z` -- see
## water_sample_at's header for `wetness`'s role. Thin wrapper around
## _blob_liquid_sample with lake_noise (sampled at the warped position) and
## water's own color set. Zone-exclusivity (see this file's own header) is
## the caller's (water_sample_at's) job, not this function's -- this is a
## pure noise-shape sampler, same as _lava_lake_sample/_oil_lake_sample below.
func _lake_water_sample(world_x: float, world_z: float) -> Dictionary:
	var w := _warp(world_x, world_z)
	var n := lake_noise.get_noise_2d(w.x, w.y)
	return _blob_liquid_sample(n, LAKE_THRESHOLD, LAKE_SHORE_BAND, DEEP_LAKE_MARGIN, SHORE_TINT_COLOR, SHALLOW_WATER_TINT_COLOR, DEEP_WATER_TINT_COLOR)

## Lava's lake-style pool sample -- same shape as _lake_water_sample, but
## lava_lake_noise/lava's own color set, plus a `glow` field (0..1, equal to
## `depth`) real water/oil samples don't carry: only actually molten lava
## (past the deep threshold, not just the charred shore ring) should emit
## light (see Chunk._build_ground_material's water-wave bake and
## ground.gdshader's own glow channel).
func _lava_lake_sample(world_x: float, world_z: float) -> Dictionary:
	var w := _warp(world_x, world_z)
	var n := lava_lake_noise.get_noise_2d(w.x, w.y)
	var sample := _blob_liquid_sample(n, LAVA_LAKE_THRESHOLD, LAVA_SHORE_BAND, LAVA_LAKE_DEEP_MARGIN, LAVA_SHORE_TINT_COLOR, LAVA_SHALLOW_TINT_COLOR, LAVA_DEEP_TINT_COLOR)
	sample["glow"] = sample.depth
	return sample

## Lava's river-style stream sample -- see _lava_lake_sample's own header.
func _lava_river_sample(world_x: float, world_z: float) -> Dictionary:
	var w := _warp(world_x, world_z)
	var n := lava_river_noise.get_noise_2d(w.x, w.y)
	var sample := _ridge_liquid_sample(n, LAVA_RIVER_HALF_WIDTH, LAVA_SHORE_BAND, LAVA_RIVER_DEEP_FRACTION, LAVA_SHORE_TINT_COLOR, LAVA_SHALLOW_TINT_COLOR, LAVA_DEEP_TINT_COLOR)
	sample["glow"] = sample.depth
	return sample

## Oil's lake-style pool sample -- see _lake_water_sample's own header. No
## glow (oil doesn't emit light).
func _oil_lake_sample(world_x: float, world_z: float) -> Dictionary:
	var w := _warp(world_x, world_z)
	var n := oil_lake_noise.get_noise_2d(w.x, w.y)
	var sample := _blob_liquid_sample(n, OIL_LAKE_THRESHOLD, OIL_SHORE_BAND, OIL_LAKE_DEEP_MARGIN, OIL_SHORE_TINT_COLOR, OIL_SHALLOW_TINT_COLOR, OIL_DEEP_TINT_COLOR)
	sample["glow"] = 0.0
	return sample

## Blends two liquid samples (each a _ridge_liquid_sample/_blob_liquid_sample
## result) by whichever has the higher `wetness`, smoothly near a tie --
## used by hazard_sample_at to merge lava's lake+river sub-features into one
## substance. Real water has no equivalent merge of its own since it's lake-
## only now (see this file's own header on why the old river feature was
## removed) -- water_sample_at is a direct pass-through to _lake_water_sample.
func _merge_two_liquid_samples(a: Dictionary, b: Dictionary) -> Dictionary:
	var blend: float = clamp(smoothstep(-0.1, 0.1, b.wetness - a.wetness), 0.0, 1.0)
	return {
		"tint": a.tint.lerp(b.tint, blend),
		"shore": lerp(a.shore, b.shore, blend),
		"depth": lerp(a.depth, b.depth, blend),
		"glow": lerp(a.get("glow", 0.0), b.get("glow", 0.0), blend),
		"wetness": lerp(a.wetness, b.wetness, blend),
	}

## Lava/oil's own version of water_sample_at -- see this file's own header
## on why this is a fully separate function rather than folded into
## water_sample_at's own merge. Neutral (white/0/0/0) outside each hazard's
## own biome-coherence gate, so a chunk far from any volcanic hotspot or
## hot/dry climate never even samples lava_lake_noise/lava_river_noise/
## oil_lake_noise at all. Returns lava's own lake+river blend where
## is_volcanic_at is true, oil's lake sample where _is_hot_dry_climate_at is
## true instead (the two gates are independent fields and could in
## principle both be true at the same point, but lava is checked first --
## the rarer, more dramatic feature wins any such coincidence, matching
## is_volcanic_at's own precedence over the climate grid in
## biome_for_world_pos).
func hazard_sample_at(world_x: float, world_z: float) -> Dictionary:
	var neutral := {"tint": Color.WHITE, "shore": 0.0, "depth": 0.0, "glow": 0.0}
	if Vector2(world_x, world_z).length() < PLAINS_RADIUS:
		return neutral
	if is_volcanic_at(world_x, world_z):
		return _merge_two_liquid_samples(_lava_lake_sample(world_x, world_z), _lava_river_sample(world_x, world_z))
	if _is_hot_dry_climate_at(world_x, world_z):
		return _oil_lake_sample(world_x, world_z)
	return neutral

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
## the lake noise threshold water_tint_at itself blends across (LAKE_THRESHOLD)
## and fading to 0 within one shore-band's width to either side -- reuses
## that same threshold/band rather than a new tuning constant, so the
## animated foam in scripts/world/ground.gdshader always lines up with the
## existing sandy-shore/shallow-water tint band instead of drifting from it.
## Baked into ground-mesh vertex-color alpha by Chunk (see
## Chunk._build_ground_mesh), since the shader itself has no noise access.
func shore_factor_at(world_x: float, world_z: float) -> float:
	var sample: Dictionary = water_sample_at(world_x, world_z)
	return sample.shore

## How far "into" water `world_x`/`world_z` is, 0..1 -- 0.0 on dry land and
## right at the water line, rising smoothly through the shallow band and
## saturating at 1.0 by the same is_deep_water_at threshold (DEEP_LAKE_MARGIN)
## rather than peaking-then-fading like shore_factor_at. Read per-pixel (not
## per-vertex, see Chunk.WATER_MASK_SIZE) by ground.gdshader to grow its wave
## normal-perturbation with distance from shore (see feature request: "small
## flat waves that fit the coast shape... add waves farther from the coast"
## -- the opposite of what a peaked shore mask alone could drive). Thin
## wrapper around water_sample_at.
func water_depth_factor_at(world_x: float, world_z: float) -> float:
	var sample: Dictionary = water_sample_at(world_x, world_z)
	return sample.depth
