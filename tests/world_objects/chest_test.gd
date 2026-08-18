extends GdUnitTestSuite
## Covers Chest.open() -- the resource-granting/interaction-blocking half
## happens synchronously (see open()'s own header on why: the economy
## should never wait on the lid-opening flourish's tweens/awaits), only the
## visual reveal and the eventual queue_free are deferred, so this only
## needs to assert what's true the instant open() returns, not wait out its
## animation.

var _wood_before: float
var _gold_before: float

const CHEST_SCENE: PackedScene = preload("res://scenes/world_objects/chest.tscn")


func before_test() -> void:
	_wood_before = GameManager.resources.get("wood", 0.0)
	_gold_before = GameManager.resources.get("gold", 0.0)


func after_test() -> void:
	GameManager.resources["wood"] = _wood_before
	GameManager.resources["gold"] = _gold_before


func _spawn_chest(loot: Dictionary) -> Node:
	var chest: Node = CHEST_SCENE.instantiate()
	chest.loot = loot
	add_child(chest)
	auto_free(chest)
	return chest


func test_open_grants_every_loot_entry_immediately() -> void:
	var chest := _spawn_chest({"wood": 40, "gold": 10})
	chest.open()
	var wood: float = GameManager.resources.get("wood", 0.0)
	var gold: float = GameManager.resources.get("gold", 0.0)
	assert_float(wood).is_equal_approx(_wood_before + 40.0, 0.001)
	assert_float(gold).is_equal_approx(_gold_before + 10.0, 0.001)


func test_open_removes_it_from_the_chests_group_immediately() -> void:
	# So a second click during the lid-opening flourish can't double-grant
	# the loot before queue_free actually happens (see open()'s own header).
	var chest := _spawn_chest({"wood": 10})
	assert_bool(chest.is_in_group("chests")).is_true()
	chest.open()
	assert_bool(chest.is_in_group("chests")).is_false()


func test_open_disables_its_collision_layer_immediately() -> void:
	var chest := _spawn_chest({"wood": 10})
	chest.open()
	assert_int(chest.collision_layer).is_equal(0)
