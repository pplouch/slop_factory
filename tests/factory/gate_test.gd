extends GdUnitTestSuite
## Covers Gate (see feature request: "add a building: gate, which is like a
## wall... but allows units to go through while retaining enemies"). Real
## move_and_slide() physics collision needs actual physics frames, not a
## tight synchronous loop, to let Jolt's broad-phase pick up a freshly-added
## CollisionShape3D (see CLAUDE.md's own note on the enemy-wall-collision
## bug this exact gotcha caused before) -- so this awaits get_tree().
## physics_frame each iteration, and disables each actor's own
## _physics_process so its AI doesn't fight the manually-set velocity here.

const GATE_SCENE: PackedScene = preload("res://scenes/factory/gate.tscn")
const BLOB_SCENE: PackedScene = preload("res://scenes/units/blob/blob.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/units/enemy/enemy.tscn")

const APPROACH_FRAMES := 90


func _spawn_gate(position: Vector3) -> Node3D:
	var gate: Node3D = GATE_SCENE.instantiate()
	gate.kind_id = "gate"
	add_child(gate, true)
	auto_free(gate)
	gate.global_position = position
	return gate


func test_gate_does_not_block_pathing_movement() -> void:
	var gate := _spawn_gate(Vector3.ZERO)
	assert_bool(gate.blocks_movement).is_false()


func test_gate_sits_on_its_own_dedicated_barrier_layer_not_walls_shared_one() -> void:
	# Wall's own collision_layer (4, "Resources") is inside Blob's own
	# collision_mask -- Gate must NOT share it, or blobs would physically
	# collide with it despite blocks_movement=false clearing the pathing grid.
	var gate := _spawn_gate(Vector3.ZERO)
	assert_int(gate.collision_layer).is_not_equal(4)


func test_a_blob_physically_passes_through_a_gate() -> void:
	var gate_pos := Vector3(50.0, 0.0, 50.0)
	_spawn_gate(gate_pos)
	var blob: CharacterBody3D = BLOB_SCENE.instantiate()
	blob.kind_id = "worker"
	add_child(blob, true)
	auto_free(blob)
	blob.set_physics_process(false)
	blob.global_position = gate_pos + Vector3(-2.0, 0.0, 0.0)

	for i in APPROACH_FRAMES:
		blob.velocity = Vector3(3.0, 0.0, 0.0)
		blob.move_and_slide()
		await get_tree().physics_frame

	assert_float(blob.global_position.x).is_greater(gate_pos.x + 1.0)


func test_an_enemy_is_blocked_by_a_gate() -> void:
	var gate_pos := Vector3(60.0, 0.0, 60.0)
	_spawn_gate(gate_pos)
	var enemy: CharacterBody3D = ENEMY_SCENE.instantiate()
	enemy.kind_id = "slime"
	add_child(enemy, true)
	auto_free(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = gate_pos + Vector3(0.0, 0.0, -2.0)

	for i in APPROACH_FRAMES:
		enemy.velocity = Vector3(0.0, 0.0, 3.0)
		enemy.move_and_slide()
		await get_tree().physics_frame

	assert_float(enemy.global_position.z).is_less(gate_pos.z - 0.5)


func test_gate_only_links_visually_to_wall_not_another_gate() -> void:
	var gate := _spawn_gate(Vector3.ZERO)
	var other_gate: Node3D = GATE_SCENE.instantiate()
	other_gate.kind_id = "gate"
	add_child(other_gate, true)
	auto_free(other_gate)

	assert_bool(gate._links_to(other_gate)).is_false()

	var wall: Node3D = load("res://scenes/factory/wall.tscn").instantiate()
	wall.kind_id = "wall"
	add_child(wall, true)
	auto_free(wall)
	assert_bool(gate._links_to(wall)).is_true()
