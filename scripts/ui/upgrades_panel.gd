extends CanvasLayer
## MainMenu's Upgrades screen -- spends MetaProgression's prestige points
## (see scripts/autoload/meta_progression.gd) on permanent bonuses that
## apply starting from the very next run. Mirrors BuildingMenu's own
## Global Upgrades section (one row per stat, built once from a shared id
## list, refreshed live) but reads/writes MetaProgression instead of
## GameManager, since these purchases persist across runs rather than
## resetting with a new World scene.

@onready var points_label: Label = $Panel/VBox/PointsLabel
@onready var rows_container: VBoxContainer = $Panel/VBox/Scroll/Rows
@onready var close_button: Button = $CloseButton
@onready var backdrop: ColorRect = $Backdrop

var _labels: Dictionary = {}
var _buttons: Dictionary = {}


## Godot lifecycle hook: builds one row per MetaProgression upgrade, starts
## hidden, and keeps refreshing live while open via MetaProgression.changed
## (fired by both a purchase here and a prestige-point award elsewhere).
func _ready() -> void:
	visible = false
	close_button.pressed.connect(close_panel)
	backdrop.gui_input.connect(_on_backdrop_gui_input)
	_build_rows()
	MetaProgression.changed.connect(_refresh)

func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()

func open_panel() -> void:
	visible = true
	_refresh()

func close_panel() -> void:
	visible = false

## Creates one row (label + buy button) per id in MetaProgression.UPGRADE_IDS.
func _build_rows() -> void:
	for upgrade_id in MetaProgression.UPGRADE_IDS:
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var button := Button.new()
		button.pressed.connect(func(): MetaProgression.try_purchase_upgrade(upgrade_id))

		var row := HBoxContainer.new()
		row.add_child(label)
		row.add_child(button)
		rows_container.add_child(row)

		_labels[upgrade_id] = label
		_buttons[upgrade_id] = button

## Refreshes the points total and every row's level/cost/affordability.
func _refresh() -> void:
	points_label.text = "Prestige Points: %d" % MetaProgression.prestige_points
	for upgrade_id in MetaProgression.UPGRADE_IDS:
		var level := MetaProgression.get_upgrade_level(upgrade_id)
		var cost := MetaProgression.get_upgrade_cost(upgrade_id)
		var display_name: String = MetaProgression.UPGRADE_DISPLAY_NAMES.get(upgrade_id, upgrade_id.capitalize())
		_labels[upgrade_id].text = "%s Lv.%d" % [display_name, level]
		_buttons[upgrade_id].text = "Upgrade (%d pts)" % cost
		_buttons[upgrade_id].disabled = not MetaProgression.can_afford_upgrade(upgrade_id)
