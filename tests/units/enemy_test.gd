extends GdUnitTestSuite
## Covers Enemy's difficulty_multiplier export (see feature request: "the
## farther the biome is... the harder the enemies") -- set by whoever
## spawns an enemy (SpawnManager/DayNightManager, from
## Biomes.enemy_difficulty_multiplier_at at the chosen spawn position)
## *before* add_child, since Enemy._ready() runs synchronously during
## add_child and every real spawn call site only sets global_position
## *after* that.

const ENEMY_SCENE: PackedScene = preload("res://scenes/units/enemy/enemy.tscn")


func _spawn_enemy(kind_id: String, difficulty_multiplier: float) -> Node3D:
	var enemy: Node3D = ENEMY_SCENE.instantiate()
	enemy.kind_id = kind_id
	enemy.difficulty_multiplier = difficulty_multiplier
	add_child(enemy, true)
	auto_free(enemy)
	return enemy


func test_higher_difficulty_multiplier_produces_a_tougher_enemy() -> void:
	var baseline := _spawn_enemy("slime", 1.0)
	var harder := _spawn_enemy("slime", 2.0)

	assert_float(harder.max_health).is_greater(baseline.max_health)
	assert_float(harder.attack_power).is_greater(baseline.attack_power)


func test_default_difficulty_multiplier_is_one() -> void:
	var enemy: Node3D = ENEMY_SCENE.instantiate()
	enemy.kind_id = "slime"
	add_child(enemy, true)
	auto_free(enemy)
	assert_float(enemy.difficulty_multiplier).is_equal(1.0)
