extends GdUnitTestSuite
## Covers BuildableStructure's ambient-light feature: a finished building
## gets a small warm OmniLight3D (never while still under construction),
## and LinkableBuilding kinds (Wall/BeltSegment/Pipe/Road -- numerous
## factory-grid pieces, not "buildings" in the sense the feature means)
## never get one at all, via the _emits_ambient_light() override.

func test_finished_building_gets_an_ambient_light_but_not_while_under_construction() -> void:
	var kind := BuildingKinds.get_kind("town_hall")
	var node: Node3D = kind.scene.instantiate()
	node.kind_id = "town_hall"
	add_child(node, true)
	auto_free(node)

	assert_object(node._building_light).is_null()
	node.add_construction_progress(999999.0)
	assert_object(node._building_light).is_not_null()
	assert_bool(node._building_light is OmniLight3D).is_true()


func test_linkable_building_never_gets_an_ambient_light() -> void:
	var kind := BuildingKinds.get_kind("wall")
	var wall: Node3D = kind.scene.instantiate()
	wall.kind_id = "wall"
	add_child(wall, true)
	auto_free(wall)

	wall.add_construction_progress(999999.0)
	assert_object(wall._building_light).is_null()


func test_ambient_light_is_only_ever_spawned_once() -> void:
	var kind := BuildingKinds.get_kind("storage_depot")
	var node: Node3D = kind.scene.instantiate()
	node.kind_id = "storage_depot"
	add_child(node, true)
	auto_free(node)

	node.add_construction_progress(999999.0)
	var first_light: OmniLight3D = node._building_light
	# A finished structure's _apply_construction_visual(1.0) can in
	# principle run again (e.g. a second add_construction_progress call
	# after is_under_construction is already false is a no-op per that
	# method's own early-out, but _refresh_construction_bar/the ambient-
	# light check are also reached via the "already finished" branch of
	# add_construction_progress, so this guards against a duplicate light).
	node._apply_construction_visual(1.0)
	assert_object(node._building_light).is_same(first_light)
