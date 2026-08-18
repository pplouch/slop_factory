extends GdUnitTestSuite
## Covers DebugMenu: each button emits the signal World actually wires up
## to a manager (see world.gd's debug_menu.*_requested.connect(...) calls),
## with the right arguments for the time-of-day buttons. DebugMenu is a
## pure view (see its own header) -- these tests only check "pressing this
## button fires this signal", not what a manager does in response (that's
## covered by fog_manager_test/day_night_manager_test/spawn_manager_test/
## debug_overlay_manager behavior directly).

const DEBUG_MENU_SCENE: PackedScene = preload("res://scenes/ui/debug_menu.tscn")


func _make_menu() -> Node:
	var menu := DEBUG_MENU_SCENE.instantiate()
	add_child(menu, true)
	auto_free(menu)
	return menu


func test_clear_fog_button_emits_clear_fog_requested() -> void:
	var menu := _make_menu()
	monitor_signals(menu)
	menu.get_node("Panel/VBox/ClearFogButton").pressed.emit()
	await assert_signal(menu).is_emitted("clear_fog_requested")


func test_spawn_enemies_near_base_button_emits_its_signal() -> void:
	var menu := _make_menu()
	monitor_signals(menu)
	menu.get_node("Panel/VBox/SpawnEnemiesNearBaseButton").pressed.emit()
	await assert_signal(menu).is_emitted("spawn_enemies_near_base_requested")


func test_add_resources_button_emits_its_signal() -> void:
	var menu := _make_menu()
	monitor_signals(menu)
	menu.get_node("Panel/VBox/AddResourcesButton").pressed.emit()
	await assert_signal(menu).is_emitted("add_resources_requested")


func test_time_of_day_buttons_emit_set_time_requested_with_the_right_fraction() -> void:
	var menu := _make_menu()
	monitor_signals(menu)
	menu.get_node("Panel/VBox/TimeRow/NoonButton").pressed.emit()
	await assert_signal(menu).is_emitted("set_time_requested", 0.5)
	menu.get_node("Panel/VBox/TimeRow/MidnightButton").pressed.emit()
	await assert_signal(menu).is_emitted("set_time_requested", 0.0)
	menu.get_node("Panel/VBox/TimeRow/DawnButton").pressed.emit()
	await assert_signal(menu).is_emitted("set_time_requested", 0.2)
	menu.get_node("Panel/VBox/TimeRow/DuskButton").pressed.emit()
	await assert_signal(menu).is_emitted("set_time_requested", 0.8)
