extends CanvasLayer
## The upgrade-and-hire popup opened by left-clicking the building.
##
## Both sections are built entirely from data rather than hardcoded scene
## nodes: the upgrade rows come from GameManager.UPGRADE_STATS, and the hire
## rows come from BlobKinds' registered archetypes. Adding a 6th upgrade or
## a 5th blob kind therefore needs no changes here or in the .tscn -- only
## in game_manager.gd / blob_kinds.gd.
##
## Refreshes reactively whenever GameManager's resource or upgrade signals
## fire, rather than polling every frame.

@onready var upgrade_rows_container: VBoxContainer = $Panel/Scroll/VBox/UpgradeRows
@onready var hire_rows_container: VBoxContainer = $Panel/Scroll/VBox/HireRows

var _upgrade_labels: Dictionary = {}
var _upgrade_buttons: Dictionary = {}
var _hire_buttons: Dictionary = {}


## Godot lifecycle hook: starts hidden, builds both rows sections from their
## data sources, and subscribes to GameManager so levels/costs/affordability
## stay current without any polling.
func _ready() -> void:
	visible = false
	_build_upgrade_rows()
	_build_hire_rows()
	GameManager.resource_changed.connect(func(_type, _total): _refresh())
	GameManager.upgrade_changed.connect(func(_stat, _level): _refresh())

## Opens the menu (called by World when the building is clicked) and
## refreshes it first, in case resources changed while it was closed.
func open_menu() -> void:
	visible = true
	_refresh()

## Closes the menu, e.g. via its Close button.
func close_menu() -> void:
	visible = false

## Creates one row (label + button) per stat in GameManager.UPGRADE_STATS.
func _build_upgrade_rows() -> void:
	for stat in GameManager.UPGRADE_STATS:
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var button := Button.new()
		button.pressed.connect(func(): GameManager.try_purchase_upgrade(stat))

		var row := HBoxContainer.new()
		row.add_child(label)
		row.add_child(button)
		upgrade_rows_container.add_child(row)

		_upgrade_labels[stat] = label
		_upgrade_buttons[stat] = button

## Creates one row (label + button) per archetype in BlobKinds.
func _build_hire_rows() -> void:
	for kind_id in BlobKinds.get_ordered_ids():
		var kind = BlobKinds.get_kind(kind_id)

		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s\n%s" % [kind.display_name, kind.stat_summary()]

		var button := Button.new()
		button.pressed.connect(func(): _hire(kind_id))

		var row := HBoxContainer.new()
		row.add_child(label)
		row.add_child(button)
		hire_rows_container.add_child(row)

		_hire_buttons[kind_id] = button

## Button handler for a hire row: asks the building to spend wood and spawn
## the given kind. The building (not this menu) owns spawn logic.
func _hire(kind_id: String) -> void:
	var building = get_tree().get_first_node_in_group("buildings")
	if building:
		building.hire_blob(kind_id)

## Refreshes every upgrade row (level/cost/affordability) and every hire
## row's button (cost/affordability) from current game state.
func _refresh() -> void:
	for stat in GameManager.UPGRADE_STATS:
		var level := GameManager.get_upgrade_level(stat)
		var cost := GameManager.get_upgrade_cost(stat)
		var display_name: String = GameManager.UPGRADE_DISPLAY_NAMES.get(stat, stat.capitalize())
		_upgrade_labels[stat].text = "%s Lv.%d" % [display_name, level]
		_upgrade_buttons[stat].text = "Upgrade (%d wood)" % cost
		_upgrade_buttons[stat].disabled = not GameManager.can_afford_upgrade(stat)

	for kind_id in BlobKinds.get_ordered_ids():
		var kind = BlobKinds.get_kind(kind_id)
		_hire_buttons[kind_id].text = "Hire (%d wood)" % kind.hire_cost
		_hire_buttons[kind_id].disabled = not GameManager.can_afford_cost(kind.hire_cost)
