extends GdUnitTestSuite
## Covers BlobKinds: Registry's shared get_kind/get_ordered_ids contract as
## applied to the hireable blob archetypes. Deliberately doesn't hardcode
## the exact roster or its size (new kinds get added over time, see
## CLAUDE.md's feature backlogs) -- asserts invariants every kind must
## satisfy instead, so adding a kind later can't silently break this suite.

func test_worker_is_the_default_fallback_kind() -> void:
	assert_str(BlobKinds.get_kind("worker").id).is_equal("worker")
	assert_str(BlobKinds.get_kind("definitely_not_a_real_kind").id).is_equal("worker")


func test_get_ordered_ids_includes_worker_and_has_no_duplicates() -> void:
	var ids := BlobKinds.get_ordered_ids()
	assert_array(ids).contains("worker")
	for id in ids:
		assert_int(ids.count(id)).is_equal(1)


func test_every_registered_kind_has_sane_stat_multipliers_and_cost() -> void:
	for id in BlobKinds.get_ordered_ids():
		var kind := BlobKinds.get_kind(id)
		assert_str(kind.id).is_equal(id)
		assert_int(kind.hire_cost).is_greater(0)
		assert_float(kind.speed_mult).is_greater(0.0)
		assert_float(kind.capacity_mult).is_greater(0.0)
		assert_float(kind.harvest_mult).is_greater(0.0)
		assert_float(kind.body_scale).is_greater(0.0)
		assert_float(kind.build_mult).is_greater(0.0)
		assert_int(kind.unlock_cost).is_greater_equal(0)


func test_unlock_chain_prerequisites_are_themselves_registered_kinds() -> void:
	# Every kind's `requires` (if any) must name another real kind in this
	# same registry -- a dangling prerequisite would silently make that kind
	# unlockable-forever (GameManager.can_unlock_blob_kind checks
	# is_blob_kind_unlocked(kind.requires), which just reads false for a
	# typo'd id rather than erroring).
	var ids := BlobKinds.get_ordered_ids()
	for id in ids:
		var kind := BlobKinds.get_kind(id)
		if kind.requires != "":
			assert_array(ids).contains(kind.requires)


func test_body_color_returns_a_real_color() -> void:
	var kind := BlobKinds.get_kind("worker")
	assert_bool(kind.body_color() is Color).is_true()
