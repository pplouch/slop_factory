extends GdUnitTestSuite
## Covers FogManager: sticky reveal-by-position, the "outside tracked
## coverage counts as already revealed" fallback, and the debug "Clear
## Fog" helper.

func _make_fog(half_size: float) -> FogManager:
	var world := Node3D.new()
	add_child(world, true)
	auto_free(world)
	var fog := FogManager.new()
	fog.setup(world, half_size)
	return fog


func test_unrevealed_position_reads_as_not_revealed() -> void:
	var fog := _make_fog(200.0)
	assert_bool(fog.is_revealed(Vector3(150.0, 0.0, 150.0))).is_false()


func test_reveal_at_marks_only_within_vision_radius() -> void:
	var fog := _make_fog(200.0)
	fog._reveal_at(Vector3.ZERO)
	assert_bool(fog.is_revealed(Vector3.ZERO)).is_true()
	assert_bool(fog.is_revealed(Vector3(190.0, 0.0, 190.0))).is_false()


func test_positions_outside_tracked_coverage_read_as_already_revealed() -> void:
	var fog := _make_fog(50.0)
	assert_bool(fog.is_revealed(Vector3(1000.0, 0.0, 1000.0))).is_true()


func test_reveal_all_marks_a_far_tracked_position_as_revealed() -> void:
	var fog := _make_fog(200.0)
	var far_pos := Vector3(150.0, 0.0, 150.0)
	assert_bool(fog.is_revealed(far_pos)).is_false()
	fog.reveal_all()
	assert_bool(fog.is_revealed(far_pos)).is_true()
