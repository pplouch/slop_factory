extends GdUnitTestSuite
## Covers Minimap: the clip_contents fix for the reported bug ("green dots
## on the minimap border are partially covered by fog, but not entirely,
## because they're partially out of the minimap") and the world<->local
## coordinate mapping it depends on.

const MINIMAP_SCENE: PackedScene = preload("res://scenes/ui/minimap.tscn")


func _make_display() -> Control:
	var minimap_root := MINIMAP_SCENE.instantiate()
	add_child(minimap_root, true)
	auto_free(minimap_root)
	var display: Control = minimap_root.get_node("Display")
	display.size = Vector2(180, 180)
	return display


func test_display_control_clips_contents_so_offscreen_dots_never_bleed_past_the_border() -> void:
	# clip_contents is what makes Godot discard a dot's circle draw call
	# wherever it extends past this control's own rect -- without it, a dot
	# clamped to the exact edge (see _world_to_local) still spills `radius`
	# pixels beyond the border, landing outside the region the fog overlay
	# itself is confined to.
	assert_bool(_make_display().clip_contents).is_true()


func test_world_to_local_clamps_far_positions_to_the_controls_own_rect() -> void:
	var display := _make_display()
	display.set_world_bounds(75.0)
	var far: Vector2 = display._world_to_local(Vector3(10000.0, 0.0, 10000.0))
	assert_float(far.x).is_between(0.0, 180.0)
	assert_float(far.y).is_between(0.0, 180.0)


func test_world_to_local_maps_camera_center_to_the_middle_of_the_rect() -> void:
	var display := _make_display()
	display.set_world_bounds(75.0)
	var center: Vector2 = display._world_to_local(Vector3.ZERO)
	assert_float(center.x).is_equal_approx(90.0, 0.5)
	assert_float(center.y).is_equal_approx(90.0, 0.5)


func test_local_to_world_is_the_inverse_of_world_to_local() -> void:
	var display := _make_display()
	display.set_world_bounds(75.0)
	var original := Vector3(20.0, 0.0, -30.0)
	var round_tripped: Vector3 = display._local_to_world(display._world_to_local(original))
	assert_float(round_tripped.x).is_equal_approx(original.x, 0.5)
	assert_float(round_tripped.z).is_equal_approx(original.z, 0.5)
