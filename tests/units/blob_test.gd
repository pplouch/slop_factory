extends GdUnitTestSuite
## Covers Blob's torch (see feature request: "make units carry torches to
## see around them" -- night was reported as too dark), its stat scaling
## across BlobKinds archetypes, and two AI/pathfinding "gets stuck" fixes
## (see feature request: "if a unit is surrounded by unbuilt walls, it
## struggles to find the next building to build... if a unit is surrounded
## by other units, it gets stuck").

const BLOB_SCENE: PackedScene = preload("res://scenes/units/blob/blob.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/units/enemy/enemy.tscn")

## Stand-in "world" whose is_reachable can be scripted directly -- lets
## test_reachable_approach_point_falls_back_when_the_primary_angle_is_blocked
## force a specific approach angle to be rejected without needing a real
## PathingManager/BuildingManager grid wired up (that's covered separately,
## and more thoroughly, by tests/world/managers/pathing_manager_test.gd).
class FakeWorldWithOnlyOneOpenApproach extends Node3D:
	var open_point: Vector3
	var open_radius: float = 0.5
	func is_reachable(_from: Vector3, to: Vector3) -> bool:
		return to.distance_to(open_point) < open_radius


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


func test_reachable_approach_point_returns_the_primary_angle_when_it_is_already_open() -> void:
	var fake_world := FakeWorldWithOnlyOneOpenApproach.new()
	add_child(fake_world, true)
	auto_free(fake_world)
	var blob: Node3D = BLOB_SCENE.instantiate()
	blob.kind_id = "worker"
	fake_world.add_child(blob, true)
	blob.set_physics_process(false)
	blob.global_position = Vector3(3.0, 0.0, 3.0)

	var target := Vector3(5.0, 0.0, 5.0)
	var radius := 2.0
	fake_world.open_point = target + Vector3(cos(0.0), 0.0, sin(0.0)) * radius
	fake_world.open_radius = 0.6

	var chosen: Vector3 = blob._reachable_approach_point(target, 0.0, radius)
	assert_float(chosen.distance_to(fake_world.open_point)).is_less(0.6)


func test_reachable_approach_point_falls_back_when_the_primary_angle_is_blocked() -> void:
	# Only the point at angle PI/2 around `target` (one of
	# _reachable_approach_point's own APPROACH_FALLBACK_ANGLE_STEP-spaced
	# alternates) is ever reported reachable -- the requested angle (0.0)
	# must be rejected, and the fallback loop should land on the one open
	# alternate instead of just giving up and returning the blocked point.
	var fake_world := FakeWorldWithOnlyOneOpenApproach.new()
	add_child(fake_world, true)
	auto_free(fake_world)
	var blob: Node3D = BLOB_SCENE.instantiate()
	blob.kind_id = "worker"
	fake_world.add_child(blob, true)
	blob.set_physics_process(false)
	blob.global_position = Vector3(3.0, 0.0, 3.0)

	var target := Vector3(5.0, 0.0, 5.0)
	var radius := 2.0
	fake_world.open_point = target + Vector3(cos(PI / 2.0), 0.0, sin(PI / 2.0)) * radius

	var chosen: Vector3 = blob._reachable_approach_point(target, 0.0, radius)
	assert_float(chosen.distance_to(fake_world.open_point)).is_less(0.6)


func test_start_detour_avoids_a_direction_already_occupied_by_another_blob() -> void:
	# Blocks every candidate detour direction _start_detour tries except
	# one, then confirms it actually lands on that one open direction
	# instead of blindly picking a blocked one (see feature request: "unit
	# surrounded by other units gets stuck").
	# Blob has no class_name (checked -- "extends Combatant" only), so its
	# own DETOUR_SIDE_DISTANCE constant isn't reachable by a global type
	# name from here; mirrored as a literal instead (see blob.gd's own).
	const DETOUR_SIDE_DISTANCE := 2.0
	var mover := _spawn_blob("worker")
	mover.set_physics_process(false)
	mover.global_position = Vector3.ZERO
	mover.final_target = Vector3(0.0, 0.0, 10.0)

	var to_target: Vector3 = mover.final_target - mover.global_position
	to_target.y = 0.0
	var dir: Vector3 = to_target.normalized()
	var side: Vector3 = Vector3(-dir.z, 0.0, dir.x)
	var open_dir: Vector3 = side.rotated(Vector3.UP, PI / 4.0)
	var blocked_dirs: Array = [
		side, -side,
		side.rotated(Vector3.UP, -PI / 4.0), -side.rotated(Vector3.UP, PI / 4.0),
		-side.rotated(Vector3.UP, -PI / 4.0),
	]
	var escalation := 1.0 + mini(1, 4) * 0.6
	for blocked_dir in blocked_dirs:
		var blocker := _spawn_blob("worker")
		blocker.set_physics_process(false)
		blocker.global_position = mover.global_position + blocked_dir * DETOUR_SIDE_DISTANCE * escalation + dir * 1.0

	mover._start_detour()

	var expected_open_target: Vector3 = mover.global_position + open_dir * DETOUR_SIDE_DISTANCE * escalation + dir * 1.0
	assert_float(mover.move_target.distance_to(expected_open_target)).is_less(0.1)
