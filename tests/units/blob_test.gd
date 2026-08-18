extends GdUnitTestSuite
## Covers Blob's torch (see feature request: "make units carry torches to
## see around them" -- night was reported as too dark) and its stat
## scaling across BlobKinds archetypes.

const BLOB_SCENE: PackedScene = preload("res://scenes/units/blob/blob.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/units/enemy/enemy.tscn")


func _spawn_blob(kind_id: String) -> Node3D:
	var blob: Node3D = BLOB_SCENE.instantiate()
	blob.kind_id = kind_id
	add_child(blob, true)
	auto_free(blob)
	return blob


func _spawn_enemy(kind_id: String, position: Vector3) -> Node3D:
	var enemy: Node3D = ENEMY_SCENE.instantiate()
	enemy.kind_id = kind_id
	add_child(enemy, true)
	auto_free(enemy)
	enemy.global_position = position
	return enemy


func test_blob_carries_a_lit_torch() -> void:
	var blob := _spawn_blob("worker")
	var torch_light: OmniLight3D = blob.get_node("Visuals/LeftArmPivot/TorchPivot/TorchLight")
	assert_object(torch_light).is_not_null()
	assert_float(torch_light.light_energy).is_greater(0.0)
	assert_float(torch_light.omni_range).is_greater(0.0)


func test_torch_flame_is_converted_to_the_animated_sparkle_shader() -> void:
	# Blob._ready() calls GemSparkle.apply_to_emissive_meshes(self) -- the
	# flame's originally-static emissive material should come out as the
	# shared animated ShaderMaterial, same as every ore/crystal.
	var blob := _spawn_blob("worker")
	var flame: MeshInstance3D = blob.get_node("Visuals/LeftArmPivot/TorchPivot/TorchFlame")
	assert_bool(flame.get_surface_override_material(0) is ShaderMaterial).is_true()


func test_brute_hits_harder_than_worker() -> void:
	# A quick regression check that per-kind multipliers actually reach the
	# final computed stat, not just that BlobKinds' own data table has
	# different numbers on paper.
	var worker := _spawn_blob("worker")
	var brute := _spawn_blob("brute")
	assert_float(brute.attack_power).is_greater(worker.attack_power)


func test_mage_kind_flags_casts_fireball_but_worker_does_not() -> void:
	var mage := _spawn_blob("mage")
	var worker := _spawn_blob("worker")
	assert_bool(mage.casts_fireball).is_true()
	assert_bool(worker.casts_fireball).is_false()


func test_mage_engages_from_cast_range_by_spawning_a_fireball_not_melee() -> void:
	# Placed well past ATTACK_RANGE (1.3) but inside CAST_RANGE (7.0) -- a
	# melee kind would find no target here at all, but a Mage should still
	# engage, and by launching a homing Fireball rather than an instant
	# Combatant.take_damage hit (see Blob._update_combat/_cast_fireball).
	var mage := _spawn_blob("mage")
	mage.global_position = Vector3.ZERO
	var enemy := _spawn_enemy("slime", Vector3(4.0, 0.0, 0.0))

	mage._update_combat(0.1)

	# Filtered by attacker (not just "any Fireball among the parent's
	# children") since a still-in-flight Fireball from an earlier test in
	# this same suite run may not have freed itself yet -- fireballs
	# self-free asynchronously via their own _process, which these
	# synchronous _update_combat calls never actually advance a frame for.
	var fireballs := mage.get_parent().get_children().filter(func(c): return c is Fireball and c.attacker == mage)
	assert_int(fireballs.size()).is_equal(1)
	assert_object(fireballs[0].target).is_equal(enemy)
	assert_float(fireballs[0].damage).is_equal_approx(mage.attack_power, 0.001)
	# The fireball itself deals the damage on impact (see Fireball._detonate),
	# not the cast -- the enemy shouldn't have taken any damage yet.
	assert_float(enemy.health).is_equal_approx(enemy.max_health, 0.001)


func test_worker_at_the_same_range_a_mage_would_engage_from_does_not_attack_at_all() -> void:
	# Same distance as the Mage test above (4.0), well past melee's
	# ATTACK_RANGE (1.3) -- confirms the Mage's longer reach is genuinely
	# additional behavior, not a change to every kind's engagement range.
	var worker := _spawn_blob("worker")
	worker.global_position = Vector3.ZERO
	var enemy := _spawn_enemy("slime", Vector3(4.0, 0.0, 0.0))

	worker._update_combat(0.1)

	# Filtered by attacker -- see the mage test above's own note on why.
	var fireballs := worker.get_parent().get_children().filter(func(c): return c is Fireball and c.attacker == worker)
	assert_int(fireballs.size()).is_equal(0)
	assert_float(enemy.health).is_equal_approx(enemy.max_health, 0.001)
