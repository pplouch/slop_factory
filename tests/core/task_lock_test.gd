extends GdUnitTestSuite
## Covers TaskLock: counts how many live blobs currently target a given
## resource node/building, computed fresh from the "blobs" group every call
## (see its own header on why -- no separately-maintained counter to desync).
## Uses real Blob instances (auto_freed) with pending_harvest_node/
## pending_build_target set directly, rather than driving the full
## command_harvest/command_build flow -- TaskLock only ever reads those two
## fields, so this is the narrowest real setup that exercises it honestly.

const BLOB_SCENE: PackedScene = preload("res://scenes/units/blob/blob.tscn")


func _spawn_blob() -> Node3D:
	var blob: Node3D = BLOB_SCENE.instantiate()
	blob.kind_id = "worker"
	add_child(blob, true)
	auto_free(blob)
	return blob


func test_harvest_count_is_zero_for_a_target_nobody_is_working() -> void:
	var target := Node.new()
	auto_free(target)
	assert_int(TaskLock.harvest_count(get_tree(), target)).is_equal(0)


func test_harvest_count_matches_number_of_blobs_pointed_at_the_same_node() -> void:
	var target := Node.new()
	auto_free(target)
	var a := _spawn_blob()
	var b := _spawn_blob()
	var other := _spawn_blob()
	a.pending_harvest_node = target
	b.pending_harvest_node = target
	other.pending_harvest_node = null

	assert_int(TaskLock.harvest_count(get_tree(), target)).is_equal(2)


func test_build_count_matches_number_of_blobs_pointed_at_the_same_building() -> void:
	var building := Node.new()
	auto_free(building)
	var a := _spawn_blob()
	var b := _spawn_blob()
	a.pending_build_target = building
	b.pending_build_target = null

	assert_int(TaskLock.build_count(get_tree(), building)).is_equal(1)


func test_harvest_and_build_counts_dont_cross_contaminate() -> void:
	var node_target := Node.new()
	auto_free(node_target)
	var building_target := Node.new()
	auto_free(building_target)
	var blob := _spawn_blob()
	blob.pending_harvest_node = node_target

	assert_int(TaskLock.build_count(get_tree(), building_target)).is_equal(0)
	assert_int(TaskLock.harvest_count(get_tree(), node_target)).is_equal(1)
