extends CanvasLayer
## MainMenu's Options screen -- General/Audio/Video tabs (see feature
## backlog: "Options needs at least General/Audio/Video tabs"). Kept
## deliberately small: this project has no other settings anywhere to
## surface yet, so each tab holds the one or two controls that actually do
## something real right now rather than empty placeholders.

const MASTER_BUS_NAME := "Master"

@onready var close_button: Button = $CloseButton
@onready var backdrop: ColorRect = $Backdrop
@onready var volume_slider: HSlider = $Panel/VBox/TabContainer/Audio/VolumeSlider
@onready var volume_label: Label = $Panel/VBox/TabContainer/Audio/VolumeLabel
@onready var fullscreen_button: CheckButton = $Panel/VBox/TabContainer/Video/FullscreenButton
@onready var reset_button: Button = $Panel/VBox/TabContainer/General/ResetButton

const RESET_CONFIRM_WINDOW := 4.0
var _reset_armed := false
var _reset_arm_elapsed := 0.0


## Godot lifecycle hook: starts hidden, wires every control to whatever it
## actually controls, and seeds each control's starting value from current
## real state (the Master bus's current volume, the window's current mode)
## rather than an arbitrary default.
func _ready() -> void:
	visible = false
	close_button.pressed.connect(close_panel)
	backdrop.gui_input.connect(_on_backdrop_gui_input)

	var bus_index := AudioServer.get_bus_index(MASTER_BUS_NAME)
	volume_slider.value = db_to_linear(AudioServer.get_bus_volume_db(bus_index))
	volume_slider.value_changed.connect(_on_volume_changed)
	_update_volume_label()

	fullscreen_button.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen_button.toggled.connect(_on_fullscreen_toggled)

	reset_button.pressed.connect(_on_reset_pressed)

func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()

func open_panel() -> void:
	visible = true

func close_panel() -> void:
	visible = false

## Godot per-frame hook: only used to time out the reset button's
## "Are you sure?" armed state if the player never confirms (see
## _on_reset_pressed).
func _process(delta: float) -> void:
	if not _reset_armed:
		return
	_reset_arm_elapsed += delta
	if _reset_arm_elapsed >= RESET_CONFIRM_WINDOW:
		_disarm_reset()

## Slider handler: converts the 0..1 linear slider value to decibels for
## the Master bus, the actual unit AudioServer expects.
func _on_volume_changed(value: float) -> void:
	var bus_index := AudioServer.get_bus_index(MASTER_BUS_NAME)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(max(value, 0.0001)))
	AudioServer.set_bus_mute(bus_index, value <= 0.0)
	_update_volume_label()

func _update_volume_label() -> void:
	volume_label.text = "Volume: %d%%" % int(round(volume_slider.value * 100.0))

func _on_fullscreen_toggled(toggled_on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if toggled_on else DisplayServer.WINDOW_MODE_WINDOWED)

## Two-step confirm (no modal dialog needed for just one destructive
## action): the first press arms it and relabels the button as a
## confirmation prompt; a second press within RESET_CONFIRM_WINDOW actually
## wipes MetaProgression's save. Pressing anything else, or just waiting
## the window out, disarms it harmlessly.
func _on_reset_pressed() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_arm_elapsed = 0.0
		reset_button.text = "Are you sure? Click again to reset"
		return
	MetaProgression.reset()
	_disarm_reset()

func _disarm_reset() -> void:
	_reset_armed = false
	reset_button.text = "Reset Meta-Progression Save"
