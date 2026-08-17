extends CanvasLayer
## The always-visible "Build Mode" toggle button plus the structure palette
## that appears next to it once build mode is active. Purely a view: it
## reports button presses via signals and lets World tell it what to show
## (World owns all placement logic, grid state, and cost/validity checks).
##
## Extractor/Processor/Water Extractor (the only factory pieces that never
## joined the tech tree) are fixed buttons always shown. Every BuildingKinds
## entry -- Town Hall, Storage Depot, ..., and now Wall/Belt/Pipe too, see
## scripts/core/linkable_building.gd -- is built dynamically from
## BuildingKinds and only shown once GameManager reports it unlocked -- see
## _refresh_building_buttons, re-run whenever GameManager.building_unlocked
## fires so a freshly-unlocked building appears immediately without
## reopening anything.
##
## Demolishing isn't a palette selection at all -- it's a right-click on an
## existing structure while build mode is active (see World._demolish_at).

signal toggle_requested
signal kind_selected(kind_id: String)

@onready var toggle_button: Button = $ToggleButton
@onready var palette_panel: PanelContainer = $PalettePanel
@onready var extractor_button: Button = $PalettePanel/VBox/ExtractorButton
@onready var processor_button: Button = $PalettePanel/VBox/ProcessorButton
@onready var water_extractor_button: Button = $PalettePanel/VBox/WaterExtractorButton
@onready var buildings_container: VBoxContainer = $PalettePanel/VBox/BuildingsContainer

const SELECTED_TINT := Color(1.0, 0.92, 0.5)
const NORMAL_TINT := Color(1, 1, 1)

var _building_buttons: Dictionary = {}


## Godot lifecycle hook: starts with the palette collapsed, wires each fixed
## button to emit its corresponding signal, builds one (initially hidden)
## button per building kind, and subscribes to unlock changes.
func _ready() -> void:
	palette_panel.visible = false
	toggle_button.pressed.connect(func(): toggle_requested.emit())
	extractor_button.pressed.connect(func(): kind_selected.emit("extractor"))
	processor_button.pressed.connect(func(): kind_selected.emit("processor"))
	water_extractor_button.pressed.connect(func(): kind_selected.emit("water_extractor"))
	_build_building_buttons()
	GameManager.building_unlocked.connect(func(_id): _refresh_building_buttons())
	_refresh_building_buttons()

## Creates one button per BuildingKinds entry (hidden until unlocked).
func _build_building_buttons() -> void:
	for building_id in BuildingKinds.get_ordered_ids():
		var kind = BuildingKinds.get_kind(building_id)
		var button := Button.new()
		button.text = "%s (%d wood)" % [kind.display_name, kind.build_cost]
		button.pressed.connect(func(): kind_selected.emit(building_id))
		buildings_container.add_child(button)
		_building_buttons[building_id] = button

## Shows/hides each building button to match current unlock state.
func _refresh_building_buttons() -> void:
	for building_id in _building_buttons.keys():
		_building_buttons[building_id].visible = GameManager.is_building_unlocked(building_id)

## Shows/hides the structure palette and relabels the toggle button to
## reflect the current build-mode state.
func set_active(active: bool) -> void:
	palette_panel.visible = active
	toggle_button.text = "Exit Build Mode" if active else "Build Mode"

## Highlights whichever palette button corresponds to the currently
## selected structure kind.
func set_selected_kind(kind_id: String) -> void:
	extractor_button.modulate = SELECTED_TINT if kind_id == "extractor" else NORMAL_TINT
	processor_button.modulate = SELECTED_TINT if kind_id == "processor" else NORMAL_TINT
	water_extractor_button.modulate = SELECTED_TINT if kind_id == "water_extractor" else NORMAL_TINT
	for building_id in _building_buttons.keys():
		_building_buttons[building_id].modulate = SELECTED_TINT if kind_id == building_id else NORMAL_TINT
