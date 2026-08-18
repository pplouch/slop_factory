extends GdUnitTestSuite
## Covers BuildingKinds: Registry's contract as applied to the placeable
## building catalog, plus the invariants CLAUDE.md documents by hand (Wall
## spends stone not wood, every kind has a valid scene/build_labor/
## build_cost_resource). Deliberately invariant-based rather than
## hardcoding the current roster -- see blob_kinds_test.gd's own header for
## why.

func test_town_hall_wall_belt_road_are_registered_and_seeded_unlocked() -> void:
	for id in ["town_hall", "wall", "belt", "road"]:
		assert_object(BuildingKinds.get_kind(id)).is_not_null()
		assert_bool(GameManager.is_building_unlocked(id)).is_true()


func test_unknown_kind_id_returns_null_not_a_fallback() -> void:
	# BuildingKinds' fallback policy (Registry._default_id) is deliberately
	# left at "" -- it must distinguish "not a building" from "unknown id",
	# unlike BlobKinds/EnemyKinds which fall back to a default entry.
	assert_object(BuildingKinds.get_kind("not_a_real_building")).is_null()


func test_every_registered_kind_has_a_valid_scene_and_non_negative_costs() -> void:
	for id in BuildingKinds.get_ordered_ids():
		var kind := BuildingKinds.get_kind(id)
		assert_str(kind.id).is_equal(id)
		assert_object(kind.scene).is_not_null()
		assert_int(kind.build_cost).is_greater_equal(0)
		assert_int(kind.unlock_cost).is_greater_equal(0)
		assert_float(kind.build_labor).is_greater_equal(0.0)
		assert_int(kind.max_durability).is_greater_equal(0)
		assert_str(kind.build_cost_resource).is_not_empty()


func test_wall_spends_stone_not_wood() -> void:
	# See CLAUDE.md "Costs and the economy" -- Wall is the one deliberate
	# exception to every other kind's wood-denominated build_cost.
	assert_str(BuildingKinds.get_kind("wall").build_cost_resource).is_equal("stone")


func test_unlock_prerequisites_are_themselves_registered_kinds() -> void:
	var ids := BuildingKinds.get_ordered_ids()
	for id in ids:
		var kind := BuildingKinds.get_kind(id)
		if kind.requires != "":
			assert_array(ids).contains(kind.requires)


func test_foundry_requires_research_center_not_town_hall() -> void:
	# See CLAUDE.md: Foundry was deliberately moved off the otherwise-
	# uniform "everything just needs Town Hall" tier since it's a whole new
	# resource-processing layer, not a basic building.
	assert_str(BuildingKinds.get_kind("foundry").requires).is_equal("research_center")
