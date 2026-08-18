extends CanvasLayer

const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const FPS_CAPS := [0, 30, 60, 120, 144, 240]

@onready var close_button: Button = $CloseButton
@onready var backdrop: ColorRect = $Backdrop
@onready var reset_button: Button = $Panel/VBox/Tabs/General/ResetButton
@onready var ui_scale: HSlider = $Panel/VBox/Tabs/General/UiScale
@onready var ui_scale_label: Label = $Panel/VBox/Tabs/General/UiScaleLabel
@onready var volume: HSlider = $Panel/VBox/Tabs/Audio/Volume
@onready var volume_label: Label = $Panel/VBox/Tabs/Audio/VolumeLabel
@onready var mute: CheckButton = $Panel/VBox/Tabs/Audio/Mute
@onready var fullscreen: CheckButton = $Panel/VBox/Tabs/Video/Fullscreen
@onready var resolution: OptionButton = $Panel/VBox/Tabs/Video/Resolution
@onready var vsync: OptionButton = $Panel/VBox/Tabs/Video/VSync
@onready var fps_cap: OptionButton = $Panel/VBox/Tabs/Video/FpsCap
@onready var camera_speed: HSlider = $Panel/VBox/Tabs/Gameplay/CameraSpeed
@onready var camera_speed_label: Label = $Panel/VBox/Tabs/Gameplay/CameraSpeedLabel
@onready var mouse_sensitivity: HSlider = $Panel/VBox/Tabs/Gameplay/MouseSensitivity
@onready var mouse_sensitivity_label: Label = $Panel/VBox/Tabs/Gameplay/MouseSensitivityLabel

var _reset_armed := false
var _reset_elapsed := 0.0

func _ready() -> void:
	visible = false
	close_button.pressed.connect(close_panel)
	backdrop.gui_input.connect(_on_backdrop_input)
	_setup_controls()

func open_panel() -> void:
	visible = true

func close_panel() -> void:
	visible = false

func _setup_controls() -> void:
	ui_scale.value = Settings.ui_scale
	ui_scale.value_changed.connect(func(value): _set_ui_scale(value))
	_refresh_ui_scale_label()
	volume.value = Settings.master_volume
	volume.value_changed.connect(func(value): _set_volume(value))
	_refresh_volume_label()
	mute.button_pressed = Settings.master_muted
	mute.toggled.connect(func(value): _set_mute(value))
	fullscreen.button_pressed = Settings.window_mode == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen.toggled.connect(func(value): _set_fullscreen(value))
	for size in RESOLUTIONS:
		resolution.add_item("%d x %d" % [size.x, size.y])
		if size == Settings.resolution:
			resolution.select(resolution.item_count - 1)
	resolution.disabled = fullscreen.button_pressed
	resolution.item_selected.connect(func(index): _set_resolution(index))
	vsync.add_item("Off", DisplayServer.VSYNC_DISABLED)
	vsync.add_item("On", DisplayServer.VSYNC_ENABLED)
	vsync.add_item("Adaptive", DisplayServer.VSYNC_ADAPTIVE)
	for index in vsync.item_count:
		if vsync.get_item_id(index) == Settings.vsync_mode:
			vsync.select(index)
	vsync.item_selected.connect(func(index): _set_vsync(index))
	for cap in FPS_CAPS:
		fps_cap.add_item("Unlimited" if cap == 0 else "%d FPS" % cap, cap)
		if cap == Settings.max_fps:
			fps_cap.select(fps_cap.item_count - 1)
	fps_cap.item_selected.connect(func(index): _set_fps_cap(index))
	camera_speed.value = Settings.camera_pan_speed
	camera_speed.value_changed.connect(func(value): _set_camera_speed(value))
	_refresh_camera_speed_label()
	mouse_sensitivity.value = Settings.mouse_rotate_sensitivity
	mouse_sensitivity.value_changed.connect(func(value): _set_mouse_sensitivity(value))
	_refresh_mouse_sensitivity_label()
	reset_button.pressed.connect(_on_reset_pressed)

func _set_ui_scale(value: float) -> void:
	Settings.ui_scale = value
	Settings.apply_all()
	Settings.save()
	_refresh_ui_scale_label()

func _set_volume(value: float) -> void:
	Settings.master_volume = value
	Settings.master_muted = value <= 0.0
	Settings.apply_all()
	Settings.save()
	_refresh_volume_label()

func _set_mute(value: bool) -> void:
	Settings.master_muted = value
	Settings.apply_all()
	Settings.save()

func _set_fullscreen(value: bool) -> void:
	Settings.window_mode = DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED
	Settings.apply_all()
	Settings.save()
	resolution.disabled = value

func _set_resolution(index: int) -> void:
	Settings.resolution = RESOLUTIONS[index]
	Settings.apply_all()
	Settings.save()

func _set_vsync(index: int) -> void:
	Settings.vsync_mode = vsync.get_item_id(index)
	Settings.apply_all()
	Settings.save()

func _set_fps_cap(index: int) -> void:
	Settings.max_fps = fps_cap.get_item_id(index)
	Settings.apply_all()
	Settings.save()

func _set_camera_speed(value: float) -> void:
	Settings.camera_pan_speed = value
	Settings.save()
	_refresh_camera_speed_label()

func _set_mouse_sensitivity(value: float) -> void:
	Settings.mouse_rotate_sensitivity = value
	Settings.save()
	_refresh_mouse_sensitivity_label()

func _refresh_ui_scale_label() -> void:
	ui_scale_label.text = "Interface scale: %d%%" % int(round(ui_scale.value * 100.0))

func _refresh_volume_label() -> void:
	volume_label.text = "Master volume: %d%%" % int(round(volume.value * 100.0))

func _refresh_camera_speed_label() -> void:
	camera_speed_label.text = "Camera speed: %d%%" % int(round(camera_speed.value * 100.0))

func _refresh_mouse_sensitivity_label() -> void:
	mouse_sensitivity_label.text = "Mouse rotation: %d%%" % int(round(mouse_sensitivity.value * 100.0))

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close_panel()

func _process(delta: float) -> void:
	if _reset_armed:
		_reset_elapsed += delta
		if _reset_elapsed >= 4.0:
			_disarm_reset()

func _on_reset_pressed() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_elapsed = 0.0
		reset_button.text = "Click again to reset progress"
		return
	MetaProgression.reset()
	_disarm_reset()

func _disarm_reset() -> void:
	_reset_armed = false
	reset_button.text = "Reset Meta-Progression Save"
