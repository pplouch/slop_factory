extends GdUnitTestSuite
## Covers PathingManager.is_reachable -- added alongside a fix for "unit
## surrounded by unbuilt walls struggles to find the next building to
## build": compute_path's own empty-Array return means "already clear, no
## waypoints needed" in the common case, but is *also* what
## AStarGrid2D.get_id_path returns when a point is genuinely unreachable
## (e.g. fully enclosed by solid cells), and that ambiguity is exactly what
## let a blob's approach-point selection walk straight at a point it could
## never actually reach. is_reachable exists specifically to tell those two
## cases apart.

func _make_pathing_manager() -> PathingManager:
	var pathing := PathingManager.new()
	pathing.setup()
	return pathing


## Marks every cell on a square ring at Chebyshev distance `radius_cells`
## from `center_cell` solid -- a closed pen with no gaps.
func _wall_off_ring(pathing: PathingManager, center_cell: Vector2i, radius_cells: int) -> void:
	for gx in range(-radius_cells, radius_cells + 1):
		for gy in range(-radius_cells, radius_cells + 1):
			if maxi(absi(gx), absi(gy)) != radius_cells:
				continue
			pathing.mark_cell(center_cell + Vector2i(gx, gy), true)


func test_a_point_outside_a_fully_enclosed_ring_is_not_reachable_from_inside_it() -> void:
	var pathing := _make_pathing_manager()
	var center_cell := Vector2i(10, 10)
	_wall_off_ring(pathing, center_cell, 2)
	var inside := BuildingManager.grid_to_world(center_cell) + Vector3(0.3, 0.0, 0.3)
	var outside := BuildingManager.grid_to_world(center_cell) + Vector3(0.0, 0.0, (2 + 3) * BuildingManager.GRID_CELL_SIZE)

	assert_bool(pathing.is_reachable(inside, outside)).is_false()


func test_another_point_inside_the_same_enclosed_ring_is_still_reachable() -> void:
	var pathing := _make_pathing_manager()
	var center_cell := Vector2i(10, 10)
	_wall_off_ring(pathing, center_cell, 2)
	var center_world := BuildingManager.grid_to_world(center_cell)
	var inside_a := center_world + Vector3(0.3, 0.0, 0.3)
	var inside_b := center_world + Vector3(-0.3, 0.0, -0.3)

	assert_bool(pathing.is_reachable(inside_a, inside_b)).is_true()


func test_an_unobstructed_point_is_reachable() -> void:
	var pathing := _make_pathing_manager()
	assert_bool(pathing.is_reachable(Vector3.ZERO, Vector3(10.0, 0.0, 10.0))).is_true()


func test_is_reachable_matches_compute_path_when_a_real_route_exists() -> void:
	# Regression guard on the relationship between the two: is_reachable
	# should never say "reachable" for a from/to pair compute_path can't
	# actually route between, since Blob._set_destination still relies on
	# compute_path's own waypoints once is_reachable has given the go-ahead.
	# The gap is left on the *east* side specifically, not the north cell
	# directly on the straight inside->outside line -- leaving the north
	# cell solid forces a real bent detour through the east gap instead of
	# compute_path correctly (and unhelpfully, for this test) reporting
	# "already a clear straight line" with no waypoints needed.
	var pathing := _make_pathing_manager()
	var center_cell := Vector2i(-20, -20)
	for gx in range(-2, 3):
		for gy in range(-2, 3):
			if maxi(absi(gx), absi(gy)) != 2:
				continue
			if gx == 2 and gy == 0:
				continue
			pathing.mark_cell(center_cell + Vector2i(gx, gy), true)
	var center_world := BuildingManager.grid_to_world(center_cell)
	var inside := center_world + Vector3(0.3, 0.0, 0.3)
	var outside := center_world + Vector3(0.0, 0.0, 5.0 * BuildingManager.GRID_CELL_SIZE)

	assert_bool(pathing.is_reachable(inside, outside)).is_true()
	assert_array(pathing.compute_path(inside, outside)).is_not_empty()
