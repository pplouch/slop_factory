extends GdUnitTestSuite
## Covers GridDirections: the shared 4-cardinal-offset constant every
## neighbor-scanning LinkableBuilding (Wall/BeltSegment/Pipe/Road) and
## World's own grid code reads from -- a regression guard against a typo'd
## offset silently breaking every one of them at once.

func test_has_exactly_the_four_cardinal_keys() -> void:
	var keys := GridDirections.CARDINAL_OFFSETS.keys()
	assert_int(keys.size()).is_equal(4)
	for key in ["pos_x", "neg_x", "pos_z", "neg_z"]:
		assert_array(keys).contains(key)


func test_offsets_are_unit_length_and_point_the_documented_direction() -> void:
	assert_that(GridDirections.CARDINAL_OFFSETS["pos_x"]).is_equal(Vector2i(1, 0))
	assert_that(GridDirections.CARDINAL_OFFSETS["neg_x"]).is_equal(Vector2i(-1, 0))
	assert_that(GridDirections.CARDINAL_OFFSETS["pos_z"]).is_equal(Vector2i(0, 1))
	assert_that(GridDirections.CARDINAL_OFFSETS["neg_z"]).is_equal(Vector2i(0, -1))


func test_offsets_are_pairwise_opposite() -> void:
	var offsets: Dictionary = GridDirections.CARDINAL_OFFSETS
	assert_that(offsets["pos_x"] + offsets["neg_x"]).is_equal(Vector2i.ZERO)
	assert_that(offsets["pos_z"] + offsets["neg_z"]).is_equal(Vector2i.ZERO)
