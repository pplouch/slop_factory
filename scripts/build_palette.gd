extends CanvasLayer
## The always-visible "Build Mode" toggle button plus the structure palette
## that appears next to it once build mode is active. Purely a view: it
## reports button presses via signals and lets World tell it what to show
## (World owns all placement logic, grid state, and cost/validity checks).

signal toggle_requested
signal kind_selected(kind_id: String)

@onready var toggle_button: Button = $ToggleButton
@onready var palette_panel: PanelContainer = $PalettePanel
@onready var extractor_button: Button = $PalettePanel/VBox/ExtractorButton
@onready var processor_button: Button = $PalettePanel/VBox/ProcessorButton
@onready var belt_button: Button = $PalettePanel/VBox/BeltButton

const SELECTED_TINT := Color(1.0, 0.92, 0.5)
const NORMAL_TINT := Color(1, 1, 1)


## Godot lifecycle hook: starts with the palette collapsed and wires each
## button to emit its corresponding signal.
func _ready() -> void:
	palette_panel.visible = false
	toggle_button.pressed.connect(func(): toggle_requested.emit())
	extractor_button.pressed.connect(func(): kind_selected.emit("extractor"))
	processor_button.pressed.connect(func(): kind_selected.emit("processor"))
	belt_button.pressed.connect(func(): kind_selected.emit("belt"))

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
	belt_button.modulate = SELECTED_TINT if kind_id == "belt" else NORMAL_TINT
