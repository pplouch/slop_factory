extends GdUnitTestSuite
## Covers EnemyKinds: Registry's contract as applied to the hostile-
## creature catalog, plus its own extra invariant (body_type must be one
## of Enemy.tscn's three pre-built rigs).

const VALID_BODY_TYPES := ["blob", "quadruped", "humanoid"]


func test_slime_is_the_default_fallback_kind() -> void:
	assert_str(EnemyKinds.get_kind("slime").id).is_equal("slime")
	assert_str(EnemyKinds.get_kind("definitely_not_a_real_kind").id).is_equal("slime")


func test_get_ordered_ids_includes_slime_and_has_no_duplicates() -> void:
	var ids := EnemyKinds.get_ordered_ids()
	assert_array(ids).contains("slime")
	for id in ids:
		assert_int(ids.count(id)).is_equal(1)


func test_every_registered_kind_has_sane_multipliers_and_a_valid_body_type() -> void:
	for id in EnemyKinds.get_ordered_ids():
		var kind := EnemyKinds.get_kind(id)
		assert_str(kind.id).is_equal(id)
		assert_float(kind.health_mult).is_greater(0.0)
		assert_float(kind.attack_mult).is_greater(0.0)
		assert_float(kind.speed_mult).is_greater(0.0)
		assert_float(kind.body_scale).is_greater(0.0)
		assert_array(VALID_BODY_TYPES).contains(kind.body_type)
