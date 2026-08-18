extends GdUnitTestSuite
## Covers MetaProgression: the only disk-persisted state in the project
## (see its own header). reset() is reused directly for each test's own
## clean slate (before_test/after_test) rather than duplicating its logic --
## but reset() also writes user://meta_progression.cfg, and this suite must
## never actually erase whatever real progression the player has saved on
## this machine. So before()/after() (each run once for the whole suite,
## not per test) separately snapshot/restore the real on-disk values around
## every test's own reset() churn, and re-save that real snapshot at the
## very end.

var _real_prestige_points: int
var _real_upgrade_levels: Dictionary


func before() -> void:
	_real_prestige_points = MetaProgression.prestige_points
	_real_upgrade_levels = MetaProgression.upgrade_levels.duplicate()


func after() -> void:
	MetaProgression.prestige_points = _real_prestige_points
	MetaProgression.upgrade_levels = _real_upgrade_levels
	MetaProgression._save()


func before_test() -> void:
	MetaProgression.reset()


func after_test() -> void:
	MetaProgression.reset()


func test_earn_prestige_increments_total() -> void:
	MetaProgression.earn_prestige(50)
	assert_int(MetaProgression.prestige_points).is_equal(50)


func test_earn_prestige_ignores_non_positive_amounts() -> void:
	MetaProgression.earn_prestige(0)
	MetaProgression.earn_prestige(-10)
	assert_int(MetaProgression.prestige_points).is_equal(0)


func test_try_purchase_upgrade_fails_when_unaffordable() -> void:
	assert_bool(MetaProgression.try_purchase_upgrade("harvest")).is_false()
	assert_int(MetaProgression.get_upgrade_level("harvest")).is_equal(0)


func test_try_purchase_upgrade_spends_points_and_bumps_level() -> void:
	MetaProgression.earn_prestige(1000)
	var cost := MetaProgression.get_upgrade_cost("population")
	assert_bool(MetaProgression.try_purchase_upgrade("population")).is_true()
	assert_int(MetaProgression.get_upgrade_level("population")).is_equal(1)
	assert_int(MetaProgression.prestige_points).is_equal(1000 - cost)


func test_upgrade_cost_increases_with_level() -> void:
	MetaProgression.earn_prestige(1000)
	var cost0 := MetaProgression.get_upgrade_cost("harvest")
	MetaProgression.try_purchase_upgrade("harvest")
	var cost1 := MetaProgression.get_upgrade_cost("harvest")
	assert_int(cost1).is_greater(cost0)


func test_bonuses_are_zero_at_level_zero_and_positive_after_purchase() -> void:
	assert_float(MetaProgression.harvest_bonus_multiplier()).is_equal(1.0)
	assert_int(MetaProgression.population_bonus()).is_equal(0)
	assert_int(MetaProgression.starting_wood_bonus()).is_equal(0)

	MetaProgression.earn_prestige(1000)
	MetaProgression.try_purchase_upgrade("harvest")
	MetaProgression.try_purchase_upgrade("population")
	MetaProgression.try_purchase_upgrade("starting_wood")

	assert_float(MetaProgression.harvest_bonus_multiplier()).is_greater(1.0)
	assert_int(MetaProgression.population_bonus()).is_greater(0)
	assert_int(MetaProgression.starting_wood_bonus()).is_greater(0)


func test_reset_wipes_points_and_every_upgrade_level() -> void:
	MetaProgression.earn_prestige(1000)
	MetaProgression.try_purchase_upgrade("harvest")
	MetaProgression.reset()
	assert_int(MetaProgression.prestige_points).is_equal(0)
	for upgrade_id in MetaProgression.UPGRADE_IDS:
		assert_int(MetaProgression.get_upgrade_level(upgrade_id)).is_equal(0)
