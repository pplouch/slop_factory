extends GdUnitTestSuite
## Covers GameManager: the resource stockpile, wood/knowledge spending,
## upgrade cost growth, and population cap math. GameManager is a real
## autoload singleton (persistent global state), so every test snapshots
## whatever dictionaries it touches in before_test and restores them in
## after_test -- otherwise a later test (or a later run of this same test)
## would silently inherit whatever an earlier test left behind.

var _resources_snapshot: Dictionary
var _upgrade_levels_snapshot: Dictionary


func before_test() -> void:
	_resources_snapshot = GameManager.resources.duplicate()
	_upgrade_levels_snapshot = GameManager.upgrade_levels.duplicate()


func after_test() -> void:
	GameManager.resources = _resources_snapshot
	GameManager.upgrade_levels = _upgrade_levels_snapshot


func test_add_resource_increments_total() -> void:
	var before := GameManager.get_resource("wood")
	GameManager.add_resource("wood", 25)
	assert_int(GameManager.get_resource("wood")).is_equal(before + 25)


func test_add_resource_ignores_zero_amount_without_erroring() -> void:
	var before := GameManager.get_resource("wood")
	GameManager.add_resource("wood", 0)
	assert_int(GameManager.get_resource("wood")).is_equal(before)


func test_get_resource_defaults_to_zero_for_unknown_type() -> void:
	assert_int(GameManager.get_resource("unobtainium")).is_equal(0)


func test_try_spend_fails_when_unaffordable_and_leaves_stockpile_untouched() -> void:
	GameManager.resources["stone"] = 5
	assert_bool(GameManager.try_spend("stone", 100)).is_false()
	assert_int(GameManager.get_resource("stone")).is_equal(5)


func test_try_spend_succeeds_and_deducts_exactly() -> void:
	GameManager.resources["stone"] = 50
	assert_bool(GameManager.try_spend("stone", 20)).is_true()
	assert_int(GameManager.get_resource("stone")).is_equal(30)


func test_can_afford_matches_try_spend_outcome() -> void:
	GameManager.resources["planks"] = 10
	assert_bool(GameManager.can_afford("planks", 11)).is_false()
	assert_bool(GameManager.can_afford("planks", 10)).is_true()


func test_upgrade_cost_increases_with_level() -> void:
	GameManager.upgrade_levels["speed"] = 0
	var cost0 := GameManager.get_upgrade_cost("speed")
	GameManager.upgrade_levels["speed"] = 1
	var cost1 := GameManager.get_upgrade_cost("speed")
	assert_int(cost1).is_greater(cost0)


func test_try_purchase_upgrade_spends_wood_and_bumps_level() -> void:
	GameManager.resources["wood"] = 1000
	GameManager.upgrade_levels["strength"] = 0
	var cost := GameManager.get_upgrade_cost("strength")
	assert_bool(GameManager.try_purchase_upgrade("strength")).is_true()
	assert_int(GameManager.get_upgrade_level("strength")).is_equal(1)
	assert_int(GameManager.get_resource("wood")).is_equal(1000 - cost)


func test_try_purchase_upgrade_fails_and_does_not_change_level_when_unaffordable() -> void:
	GameManager.resources["wood"] = 0
	GameManager.upgrade_levels["capacity"] = 0
	assert_bool(GameManager.try_purchase_upgrade("capacity")).is_false()
	assert_int(GameManager.get_upgrade_level("capacity")).is_equal(0)


func test_speed_multiplier_increases_with_upgrade_level() -> void:
	GameManager.upgrade_levels["speed"] = 0
	var base := GameManager.get_speed_multiplier()
	GameManager.upgrade_levels["speed"] = 3
	assert_float(GameManager.get_speed_multiplier()).is_greater(base)


func test_population_cap_matches_base_plus_meta_plus_houses_formula() -> void:
	# A formula-consistency check rather than a hardcoded magic number --
	# protects against a future refactor silently dropping one of the three
	# contributions (base allowance, MetaProgression's permanent bonus,
	# finished Houses) without pinning today's exact house count, which
	# depends on whatever else is in the live scene tree.
	var expected: int = GameManager.BASE_POPULATION_CAP + MetaProgression.population_bonus() + GameManager.get_house_count() * GameManager.POPULATION_PER_HOUSE
	assert_int(GameManager.get_population_cap()).is_equal(expected)


func test_house_population_bonus_only_counts_once_finished() -> void:
	var kind := BuildingKinds.get_kind("house")
	var house: Node3D = kind.scene.instantiate()
	house.kind_id = "house"
	add_child(house, true)
	auto_free(house)

	var cap_under_construction := GameManager.get_population_cap()
	house.add_construction_progress(999999.0)
	var cap_after_finish := GameManager.get_population_cap()

	assert_int(cap_after_finish - cap_under_construction).is_equal(GameManager.POPULATION_PER_HOUSE)


func test_can_hire_more_false_once_population_cap_reached() -> void:
	# Rather than actually spawning FOUNDER_BLOB_COUNT+ blobs, this checks
	# the gate's own logic directly against the two numbers it compares.
	assert_bool(GameManager.can_hire_more()).is_equal(GameManager.get_current_population() < GameManager.get_population_cap())
