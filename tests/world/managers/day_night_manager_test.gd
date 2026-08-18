extends GdUnitTestSuite
## Covers DayNightManager: the pure day/time-fraction math (current_day,
## time_of_day_fraction, is_night), the noon-start fix (see setup()), the
## debug time-jump helper, and the weekly wave trigger. A fresh
## DayNightManager.new() is safe to use without calling setup() at all for
## the pure-math tests -- _apply_lighting() (called by set_time_fraction)
## guards every _sun/_sky_material access with `if _sun:`/`if _sky_material:`,
## so it no-ops safely with both left null.

func test_current_day_starts_at_one_and_increments_after_one_full_day_length() -> void:
	var manager := DayNightManager.new()
	assert_int(manager.current_day()).is_equal(1)
	manager._elapsed_seconds = DayNightManager.DAY_LENGTH_SECONDS + 1.0
	assert_int(manager.current_day()).is_equal(2)


func test_time_of_day_fraction_wraps_within_the_current_day() -> void:
	var manager := DayNightManager.new()
	manager._elapsed_seconds = DayNightManager.DAY_LENGTH_SECONDS * 1.25
	assert_float(manager.time_of_day_fraction()).is_equal_approx(0.25, 0.001)


func test_is_night_straddles_the_midnight_boundary() -> void:
	var manager := DayNightManager.new()
	manager.set_time_fraction(0.0)
	assert_bool(manager.is_night()).is_true()
	manager.set_time_fraction(0.5)
	assert_bool(manager.is_night()).is_false()
	manager.set_time_fraction(0.9)
	assert_bool(manager.is_night()).is_true()


func test_set_time_fraction_preserves_the_current_day_count() -> void:
	var manager := DayNightManager.new()
	manager._elapsed_seconds = DayNightManager.DAY_LENGTH_SECONDS * 6.5  # deep into day 7
	var day_before := manager.current_day()
	manager.set_time_fraction(0.1)
	assert_int(manager.current_day()).is_equal(day_before)


func test_set_time_fraction_is_safe_with_no_sun_or_sky_assigned() -> void:
	# setup() was never called here -- must not crash on a null _sun/
	# _sky_material dereference.
	var manager := DayNightManager.new()
	manager.set_time_fraction(0.5)
	assert_float(manager.time_of_day_fraction()).is_equal_approx(0.5, 0.001)


func test_setup_starts_the_game_at_noon_not_midnight() -> void:
	# Regression test for the exact bug reported: the game used to start at
	# _elapsed_seconds = 0.0 (midnight), reading as night from the first
	# frame. setup() must seed noon and apply it immediately.
	var world := Node3D.new()
	add_child(world, true)
	auto_free(world)
	var sun := DirectionalLight3D.new()
	auto_free(sun)

	var manager := DayNightManager.new()
	manager.setup(world, sun, null)

	assert_bool(manager.is_night()).is_false()
	assert_float(manager.time_of_day_fraction()).is_equal_approx(0.5, 0.001)
	assert_float(sun.light_energy).is_equal_approx(DayNightManager.DAY_LIGHT_ENERGY, 0.001)


func test_process_spawns_exactly_one_wave_on_day_seven_and_not_again_the_same_day() -> void:
	var world := Node3D.new()
	add_child(world, true)
	auto_free(world)
	var manager := DayNightManager.new()
	manager.setup(world, null, null)
	manager._elapsed_seconds = DayNightManager.DAY_LENGTH_SECONDS * (DayNightManager.WAVE_INTERVAL_DAYS - 1) + 1.0

	var before: Array = world.get_tree().get_nodes_in_group("enemies")
	manager.process(0.0)
	var after_first: Array = world.get_tree().get_nodes_in_group("enemies")
	manager.process(0.0)
	var after_second: Array = world.get_tree().get_nodes_in_group("enemies")

	var spawned_first := after_first.filter(func(n): return not before.has(n))
	assert_int(spawned_first.size()).is_equal(DayNightManager.WAVE_ENEMY_COUNT)
	assert_int(after_second.size()).is_equal(after_first.size())
