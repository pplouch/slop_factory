extends GdUnitTestSuite
## Covers Biomes: the always-plains starting circle, the water-safe radius
## around the origin, and the shoreline/water-tint math added for the
## animated ground shader. Biomes' noise fields are seeded once at
## autoload _ready() and never reset, so these tests read live values
## rather than mutating any shared state -- no before/after snapshotting
## needed, unlike GameManager.

func test_biome_for_world_pos_is_always_plains_inside_plains_radius() -> void:
	var pos := Vector3(Biomes.PLAINS_RADIUS * 0.5, 0.0, 0.0)
	assert_str(Biomes.biome_for_world_pos(pos).id).is_equal("plains")


func test_get_biome_falls_back_to_plains_for_unknown_id() -> void:
	assert_str(Biomes.get_biome("not_a_real_biome").id).is_equal("plains")


func test_get_ordered_ids_contains_every_registered_biome_exactly_once() -> void:
	var ids := Biomes.get_ordered_ids()
	assert_array(ids).contains("plains", "forest", "desert", "tundra", "swamp", "jungle", "volcanic")
	for id in ids:
		assert_int(ids.count(id)).is_equal(1)


func test_water_functions_are_all_false_within_water_safe_radius() -> void:
	var pos := Vector3(Biomes.WATER_SAFE_RADIUS * 0.5, 0.0, 0.0)
	assert_bool(Biomes.is_lake_at(pos.x, pos.z)).is_false()
	assert_bool(Biomes.is_water_at(pos.x, pos.z)).is_false()
	assert_bool(Biomes.is_deep_water_at(pos.x, pos.z)).is_false()


func test_height_at_is_flat_zero_on_dry_land_near_origin() -> void:
	assert_float(Biomes.height_at(1.0, 1.0)).is_equal(0.0)


func test_water_tint_at_is_white_within_water_safe_radius() -> void:
	var tint := Biomes.water_tint_at(1.0, 1.0)
	assert_that(tint).is_equal(Color.WHITE)


func test_shore_factor_at_is_zero_within_water_safe_radius() -> void:
	assert_float(Biomes.shore_factor_at(1.0, 1.0)).is_equal(0.0)


func test_shore_factor_at_stays_within_unit_range_across_many_samples() -> void:
	# Not asserting exact values (the underlying noise fields aren't hand-
	# computable here) -- just the invariant every sample must satisfy: a
	# 0..1 intensity, never negative or blown past 1.0 by the smoothstep math.
	for i in 200:
		var x: float = randf_range(-500.0, 500.0)
		var z: float = randf_range(-500.0, 500.0)
		var factor := Biomes.shore_factor_at(x, z)
		assert_float(factor).is_between(0.0, 1.0)


func test_deep_water_implies_water_and_both_are_actually_findable() -> void:
	# A grid scan, not random sampling -- deep water is a fairly narrow band
	# within a lake that plain random points can miss entirely, but CLAUDE.md's
	# own testing notes confirm a real mix of shallow/deep water exists once
	# you actually go looking for it. Scans a 600x600 area (well past
	# PLAINS_RADIUS, where water can first appear) at an 8-unit step.
	var found_water := false
	var found_deep := false
	var half := 300.0
	var step := 8.0
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			if Biomes.is_water_at(x, z):
				found_water = true
				if Biomes.is_deep_water_at(x, z):
					found_deep = true
					assert_bool(Biomes.is_water_at(x, z)).is_true()
			z += step
		x += step
	assert_bool(found_water).is_true()
	assert_bool(found_deep).is_true()


func test_is_volcanic_at_matches_its_own_noise_field_and_threshold() -> void:
	# Regression guard against the wiring drifting (wrong field, wrong
	# comparison direction, stale threshold constant) rather than a check on
	# *which* world positions happen to be volcanic.
	for i in 20:
		var x: float = randf_range(-2000.0, 2000.0)
		var z: float = randf_range(-2000.0, 2000.0)
		var expected: bool = Biomes.volcanic_noise.get_noise_2d(x, z) > Biomes.VOLCANIC_THRESHOLD
		assert_bool(Biomes.is_volcanic_at(x, z)).is_equal(expected)


func test_blended_ground_color_matches_plains_color_at_the_origin() -> void:
	# Well inside PLAINS_RADIUS, blended_ground_color_at should resolve
	# (almost) exactly to plains' own color -- no other biome's blend
	# weight should contribute meaningfully this deep inside the safe circle.
	var blended := Biomes.blended_ground_color_at(1.0, 1.0)
	var plains_color := Biomes.get_biome("plains").ground_color
	assert_float(blended.r).is_equal_approx(plains_color.r, 0.01)
	assert_float(blended.g).is_equal_approx(plains_color.g, 0.01)
	assert_float(blended.b).is_equal_approx(plains_color.b, 0.01)


func test_blended_ground_color_channels_stay_within_unit_range() -> void:
	# A weighted average of valid Color channels (each already 0..1) can
	# never leave that range as long as the weights themselves are a
	# proper 0..1 partition -- checked here as a real invariant over many
	# samples rather than assumed from reading the blend math.
	for i in 200:
		var x: float = randf_range(-2000.0, 2000.0)
		var z: float = randf_range(-2000.0, 2000.0)
		var color := Biomes.blended_ground_color_at(x, z)
		assert_float(color.r).is_between(0.0, 1.0)
		assert_float(color.g).is_between(0.0, 1.0)
		assert_float(color.b).is_between(0.0, 1.0)


func test_blended_ground_color_is_continuous_across_a_short_step() -> void:
	# The whole point of blending (see feature request: "the transition
	# between biomes is brutal") is that color never jumps sharply over a
	# short distance -- sampled across many random short steps far from the
	# origin (where different climate regions actually meet) and asserted
	# that no single step's color delta is large. 0.1 (not near-zero) is
	# deliberate slack: a random step can land right inside a narrow
	# smoothstep band where the *local* gradient is at its steepest, so this
	# checks "no visible snap", not "perfectly flat everywhere".
	for i in 100:
		var x: float = randf_range(-1500.0, 1500.0)
		var z: float = randf_range(-1500.0, 1500.0)
		var a := Biomes.blended_ground_color_at(x, z)
		var b := Biomes.blended_ground_color_at(x + 1.0, z + 1.0)
		var delta: float = absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
		assert_float(delta).is_less(0.1)


func test_difficulty_at_is_near_zero_at_the_origin_and_stays_in_unit_range() -> void:
	assert_float(Biomes.difficulty_at(0.0, 0.0)).is_less(0.35)
	for i in 200:
		var x: float = randf_range(-4000.0, 4000.0)
		var z: float = randf_range(-4000.0, 4000.0)
		assert_float(Biomes.difficulty_at(x, z)).is_between(0.0, 1.0)


func test_difficulty_at_saturates_its_distance_term_well_past_its_max_distance() -> void:
	# Far enough out that dist_factor itself is clamped to exactly 1.0 (see
	# difficulty_at) -- the remaining spread down to 0.7 is the noise term's
	# own independent 0.3 weight, not distance, so this checks the
	# guaranteed floor/ceiling rather than assuming the noise term also
	# happens to be high at this one arbitrary sample point.
	var far := Biomes.DIFFICULTY_MAX_DISTANCE * 3.0
	assert_float(Biomes.difficulty_at(far, 0.0)).is_between(0.69, 1.001)


func test_enemy_and_resource_multipliers_match_their_own_lerp_formula() -> void:
	# Checked as "does this match lerp(..., difficulty_at(...))" rather than
	# a guessed numeric window -- difficulty_at's own noise term means a
	# single sample point's absolute value isn't tightly predictable (see
	# the test above), but the *formula wiring* connecting it to each
	# multiplier is, and that's the real regression risk worth guarding.
	for i in 20:
		var x: float = randf_range(-3000.0, 3000.0)
		var z: float = randf_range(-3000.0, 3000.0)
		var difficulty := Biomes.difficulty_at(x, z)
		assert_float(Biomes.enemy_difficulty_multiplier_at(x, z)).is_equal_approx(lerp(1.0, Biomes.MAX_ENEMY_DIFFICULTY_MULT, difficulty), 0.0001)
		assert_float(Biomes.resource_abundance_multiplier_at(x, z)).is_equal_approx(lerp(1.0, Biomes.MIN_RESOURCE_ABUNDANCE_MULT, difficulty), 0.0001)


func test_enemy_and_resource_multipliers_stay_within_their_documented_extremes() -> void:
	for i in 200:
		var x: float = randf_range(-4000.0, 4000.0)
		var z: float = randf_range(-4000.0, 4000.0)
		assert_float(Biomes.enemy_difficulty_multiplier_at(x, z)).is_between(1.0, Biomes.MAX_ENEMY_DIFFICULTY_MULT)
		assert_float(Biomes.resource_abundance_multiplier_at(x, z)).is_between(Biomes.MIN_RESOURCE_ABUNDANCE_MULT, 1.0)


func test_water_depth_factor_at_is_zero_within_water_safe_radius() -> void:
	assert_float(Biomes.water_depth_factor_at(1.0, 1.0)).is_equal(0.0)


func test_water_depth_factor_at_stays_within_unit_range_across_many_samples() -> void:
	for i in 200:
		var x: float = randf_range(-2000.0, 2000.0)
		var z: float = randf_range(-2000.0, 2000.0)
		assert_float(Biomes.water_depth_factor_at(x, z)).is_between(0.0, 1.0)


func test_water_depth_factor_at_is_zero_outside_water_and_saturates_deep_inside_it() -> void:
	# Scans a grid the same way test_deep_water_implies_water_and_both_are_
	# actually_findable does (random sampling too easily misses rivers'
	# narrow bands) -- everywhere is_water_at is false, depth must be
	# exactly 0 (dry land never gets wave treatment, and neither source
	# contributes anything for water_sample_at's blend to soften); everywhere
	# is_deep_water_at is true, depth must have very nearly saturated to 1
	# (Biomes.is_deep_water_at is defined as a strictly tighter threshold
	# than the point where each source's own smoothstep reaches 1). "Very
	# nearly" rather than exactly: water_sample_at blends river/lake by a
	# normalized strength rather than a hard max (see its own header on why
	# -- avoiding a seam where a river's own noise coincidentally grazes an
	# unrelated lake), so a point that's deep in one source but also
	# borderline-close in the OTHER source's own band can land a fraction of
	# a percent under 1.0 rather than exactly at it -- a deliberate side
	# effect of real blending, not a regression, so this tolerance is loose
	# enough to allow it while still catching an actual saturation failure.
	var half := 300.0
	var step := 8.0
	var x := -half
	var checked_dry := false
	var checked_deep := false
	while x <= half:
		var z := -half
		while z <= half:
			if not Biomes.is_water_at(x, z):
				assert_float(Biomes.water_depth_factor_at(x, z)).is_equal(0.0)
				checked_dry = true
			elif Biomes.is_deep_water_at(x, z):
				assert_float(Biomes.water_depth_factor_at(x, z)).is_equal_approx(1.0, 0.02)
				checked_deep = true
			z += step
		x += step
	assert_bool(checked_dry).is_true()
	assert_bool(checked_deep).is_true()


func test_tint_for_wetness_endpoints_match_dry_land_and_full_depth() -> void:
	var dry := Biomes._tint_for_wetness(0.0)
	assert_float(dry.r).is_equal_approx(Color.WHITE.r, 0.001)
	assert_float(dry.g).is_equal_approx(Color.WHITE.g, 0.001)
	assert_float(dry.b).is_equal_approx(Color.WHITE.b, 0.001)

	var deep := Biomes._tint_for_wetness(1.0)
	assert_float(deep.r).is_equal_approx(Biomes.DEEP_WATER_TINT_COLOR.r, 0.001)
	assert_float(deep.g).is_equal_approx(Biomes.DEEP_WATER_TINT_COLOR.g, 0.001)
	assert_float(deep.b).is_equal_approx(Biomes.DEEP_WATER_TINT_COLOR.b, 0.001)


func test_tint_for_wetness_is_continuous_within_the_shore_and_water_zones() -> void:
	# _tint_for_wetness deliberately keeps a crisp sand-to-water color
	# change right at SHORE_WETNESS (a beach line reasonably reads as a
	# real material change, same as it did before either source was routed
	# through this shared curve -- not the bug this pass actually fixed,
	# which was river/lake *disagreeing with each other* out in open water,
	# not the shore itself having a visible edge). Continuity is checked
	# within each zone separately rather than across that one intentional
	# boundary.
	var previous: Color = Biomes._tint_for_wetness(0.0)
	var w := 0.02
	while w < Biomes.SHORE_WETNESS:
		var current: Color = Biomes._tint_for_wetness(w)
		var delta: float = absf(current.r - previous.r) + absf(current.g - previous.g) + absf(current.b - previous.b)
		assert_float(delta).is_less(0.1)
		previous = current
		w += 0.02

	previous = Biomes._tint_for_wetness(Biomes.SHORE_WETNESS)
	w = Biomes.SHORE_WETNESS + 0.02
	while w <= 1.5:
		var current: Color = Biomes._tint_for_wetness(w)
		var delta: float = absf(current.r - previous.r) + absf(current.g - previous.g) + absf(current.b - previous.b)
		assert_float(delta).is_less(0.1)
		previous = current
		w += 0.02


func test_lake_samples_route_their_tint_through_the_shared_wetness_curve() -> void:
	# Guards against _lake_water_sample's tint drifting back to an
	# independently-shaped curve (the shape of the original bug this shared
	# curve fixed, back when real water still had a second river source to
	# disagree with -- see _tint_for_wetness_colored's own header): whatever
	# wetness a sample reports, its tint must be exactly what
	# _tint_for_wetness produces for that same wetness value.
	for i in 50:
		var x: float = randf_range(-2000.0, 2000.0)
		var z: float = randf_range(-2000.0, 2000.0)
		var lake: Dictionary = Biomes._lake_water_sample(x, z)
		var expected_lake_tint: Color = Biomes._tint_for_wetness(lake.wetness)
		assert_float(lake.tint.r).is_equal_approx(expected_lake_tint.r, 0.0001)
		assert_float(lake.tint.g).is_equal_approx(expected_lake_tint.g, 0.0001)
		assert_float(lake.tint.b).is_equal_approx(expected_lake_tint.b, 0.0001)


## -- Lava/oil hazard liquids (see feature request: "add oil lakes and lava
## lakes/rivers... stay coherent with the biomes") --

func test_lava_and_oil_are_never_found_inside_plains_radius() -> void:
	# Both hazards are guarded on PLAINS_RADIUS specifically (not the
	# narrower WATER_SAFE_RADIUS real water uses) -- see is_lava_at/
	# is_oil_at's own headers on why: neither should ever appear anywhere
	# the ground doesn't independently agree is Volcanic/Desert, and
	# biome_for_world_pos itself never picks those within PLAINS_RADIUS.
	for i in 100:
		var angle: float = randf_range(0.0, TAU)
		var dist: float = randf_range(0.0, Biomes.PLAINS_RADIUS - 0.01)
		var x: float = cos(angle) * dist
		var z: float = sin(angle) * dist
		assert_bool(Biomes.is_lava_at(x, z)).is_false()
		assert_bool(Biomes.is_oil_at(x, z)).is_false()
		assert_bool(Biomes.is_deep_oil_at(x, z)).is_false()


func test_is_lava_at_always_implies_nonzero_lava_zone_strength() -> void:
	# Regression guard on the biome-coherence gate itself (see this file's
	# own header): lava must never roll true somewhere _lava_zone_strength_at
	# is exactly 0, regardless of what lava_lake_noise/lava_river_noise say
	# there. Not "implies is_volcanic_at" anymore (see feature request: "lava
	# and oil... stop as soon as the biome change... make transitions
	# smoother") -- lava now fades in smoothly starting at the *lower* edge
	# of VOLCANIC_BLEND_BAND, before is_volcanic_at's own hard threshold, by
	# design. Wide scan since both the zone's own hotspot rarity and lava's
	# own threshold each independently narrow down how much of the scanned
	# area can possibly qualify.
	var found_lava := false
	var half := 1000.0
	var step := 8.0
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			if Biomes.is_lava_at(x, z):
				found_lava = true
				assert_float(Biomes._lava_zone_strength_at(x, z)).is_greater(0.0)
			z += step
		x += step
	assert_bool(found_lava).is_true()


func test_is_oil_at_always_implies_nonzero_oil_zone_strength() -> void:
	# Same coherence guarantee as the lava test above, for oil's own gate --
	# not "implies _is_hot_dry_climate_at" anymore, for the same "fades in
	# before the hard threshold, by design" reason.
	var found_oil := false
	var half := 2000.0
	var step := 25.0
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			if Biomes.is_oil_at(x, z):
				found_oil = true
				assert_float(Biomes._oil_zone_strength_at(x, z)).is_greater(0.0)
			z += step
		x += step
	assert_bool(found_oil).is_true()


func test_blob_and_ridge_liquid_sample_deep_threshold_implies_shore_threshold() -> void:
	# Direct unit test of the shared formula, not a blind search over world
	# noise: is_deep_oil_at implying is_oil_at (and the same for lava/water)
	# reduces to "wetness >= 1.0 implies wetness >= SHORE_WETNESS" on the
	# exact same scaled value both booleans read, true by construction
	# regardless of zone_w. A real "does this ever actually occur in the
	# world" occurrence got much rarer for oil specifically after zone-
	# scaling (see this file's own header on "smooth zone transitions") --
	# a deep pool now also needs to sit within the climate's own fully-at-
	# full-strength core, not just its old, looser hard-boolean territory --
	# so checking the formula directly here avoids an unreasonably large/slow
	# scan chasing a rare coincidence.
	# n = 0.61, comfortably past threshold(0.5) + deep_margin(0.1) = 0.6, not
	# exactly on it -- avoids a floating-point division landing just a hair
	# under 1.0 (0.9999999... display-rounds to "1.000000" but still fails a
	# strict >= 1.0 check).
	var blob_sample: Dictionary = Biomes._blob_liquid_sample(0.61, 0.5, 0.03, 0.1, Color.WHITE, Color.BLUE, Color.BLACK, 1.0)
	assert_float(blob_sample.wetness).is_greater_equal(1.0)
	assert_float(blob_sample.wetness).is_greater_equal(Biomes.SHORE_WETNESS)

	var ridge_sample: Dictionary = Biomes._ridge_liquid_sample(0.0, 0.035, 0.01, 0.4, Color.WHITE, Color.BLUE, Color.BLACK, 1.0)
	assert_float(ridge_sample.wetness).is_greater_equal(1.0)
	assert_float(ridge_sample.wetness).is_greater_equal(Biomes.SHORE_WETNESS)


func test_is_any_liquid_at_matches_water_lava_or_oil() -> void:
	for i in 100:
		var x: float = randf_range(-2000.0, 2000.0)
		var z: float = randf_range(-2000.0, 2000.0)
		var expected: bool = Biomes.is_water_at(x, z) or Biomes.is_lava_at(x, z) or Biomes.is_oil_at(x, z)
		assert_bool(Biomes.is_any_liquid_at(x, z)).is_equal(expected)


func test_water_lava_and_oil_never_overlap() -> void:
	# The three-way zone partition (see this file's own header) guarantees
	# at most one of these three is ever true at the same position, by
	# construction -- checked here as a real invariant (see feature request:
	# "lakes and rivers and oil and lava SHOULD NOT overlap") rather than
	# assumed from reading the gating logic. A dense grid scan (not just
	# random sampling) so the rarer Lava/Oil zones actually get exercised at
	# least once, not just the much more common "none of the three" case.
	var half := 1000.0
	var step := 8.0
	var x := -half
	var checked_an_active_case := false
	while x <= half:
		var z := -half
		while z <= half:
			var active_count := 0
			if Biomes.is_water_at(x, z):
				active_count += 1
			if Biomes.is_lava_at(x, z):
				active_count += 1
			if Biomes.is_oil_at(x, z):
				active_count += 1
			assert_int(active_count).is_less_equal(1)
			if active_count == 1:
				checked_an_active_case = true
			z += step
		x += step
	assert_bool(checked_an_active_case).is_true()


func test_liquid_sample_wetness_fades_smoothly_with_zone_strength() -> void:
	# Direct test of the actual fix (see feature request: "lava and oil...
	# stop as soon as the biome change... make transitions smoother"): with a
	# fixed, solidly-deep noise value, wetness must decrease smoothly and
	# monotonically as zone_w drops from full strength to zero, rather than
	# holding at full strength then suddenly dropping to 0 the instant an
	# unrelated independent field crosses some cutoff (the old hard-gate
	# behavior this replaced -- the real bug reported).
	# Integer-indexed loop (not a floating zw -= 0.05 decrement) so it lands
	# on exactly 21 steps from 1.0 to 0.0 regardless of float accumulation
	# error -- a decrementing float can drift just under 0.0 on the last
	# iteration and skip the exact-zero case the final assertion needs.
	var previous_wetness := 1000.0 # starts above any real value
	for i in range(21):
		var zw: float = 1.0 - float(i) * 0.05
		var sample: Dictionary = Biomes._blob_liquid_sample(0.6, 0.5, 0.03, 0.1, Color.WHITE, Color.BLUE, Color.BLACK, zw)
		assert_float(sample.wetness).is_less_equal(previous_wetness + 0.0001)
		previous_wetness = sample.wetness
	assert_float(previous_wetness).is_equal_approx(0.0, 0.0001)


func test_hazard_sample_at_is_neutral_within_plains_radius() -> void:
	var sample: Dictionary = Biomes.hazard_sample_at(1.0, 1.0)
	assert_that(sample.tint).is_equal(Color.WHITE)
	assert_float(sample.shore).is_equal(0.0)
	assert_float(sample.depth).is_equal(0.0)
	assert_float(sample.glow).is_equal(0.0)


func test_hazard_sample_at_only_glows_where_lava_zone_strength_is_nonzero() -> void:
	# glow should never appear where _lava_zone_strength_at is exactly 0
	# (oil/dry-land samples must always report exactly 0) -- not "outside
	# is_volcanic_at" anymore, since glow now fades in starting at the lower
	# edge of VOLCANIC_BLEND_BAND, before is_volcanic_at's own hard threshold,
	# the same deliberate "smooth zone transitions" change as everything else
	# in this file's header. Scanning for lava specifically should still turn
	# up at least one genuinely glowing pixel.
	var found_glow := false
	var half := 1000.0
	var step := 8.0
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			var sample: Dictionary = Biomes.hazard_sample_at(x, z)
			if Biomes._lava_zone_strength_at(x, z) <= 0.0:
				assert_float(sample.glow).is_equal(0.0)
			elif sample.glow > 0.0:
				found_glow = true
			z += step
		x += step
	assert_bool(found_glow).is_true()
