extends Node

const SAVE_PATH := "user://settings.cfg"
const MASTER_BUS_NAME := "Master"

var window_mode := DisplayServer.WINDOW_MODE_WINDOWED
var resolution := Vector2i(1280, 720)
var vsync_mode := DisplayServer.VSYNC_ENABLED
var max_fps := 120
var master_volume := 1.0
var master_muted := false
var ui_scale := 1.0
var camera_pan_speed := 1.0
var mouse_rotate_sensitivity := 1.0

func _ready() -> void:
	_load()
	apply_all()

func apply_all() -> void:
	DisplayServer.window_set_size(resolution)
	DisplayServer.window_set_vsync_mode(vsync_mode)
	DisplayServer.window_set_mode(window_mode)
	Engine.max_fps = max_fps
	get_tree().root.content_scale_factor = ui_scale
	var bus_index := AudioServer.get_bus_index(MASTER_BUS_NAME)
	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(max(master_volume, 0.0001)))
		AudioServer.set_bus_mute(bus_index, master_muted)

func save() -> void:
	var config := ConfigFile.new()
	config.set_value("video", "window_mode", window_mode)
	config.set_value("video", "resolution_x", resolution.x)
	config.set_value("video", "resolution_y", resolution.y)
	config.set_value("video", "vsync_mode", vsync_mode)
	config.set_value("video", "max_fps", max_fps)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "master_muted", master_muted)
	config.set_value("general", "ui_scale", ui_scale)
	config.set_value("gameplay", "camera_pan_speed", camera_pan_speed)
	config.set_value("gameplay", "mouse_rotate_sensitivity", mouse_rotate_sensitivity)
	config.save(SAVE_PATH)

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	window_mode = config.get_value("video", "window_mode", window_mode)
	resolution = Vector2i(config.get_value("video", "resolution_x", resolution.x), config.get_value("video", "resolution_y", resolution.y))
	vsync_mode = config.get_value("video", "vsync_mode", vsync_mode)
	max_fps = config.get_value("video", "max_fps", max_fps)
	master_volume = config.get_value("audio", "master_volume", master_volume)
	master_muted = config.get_value("audio", "master_muted", master_muted)
	ui_scale = config.get_value("general", "ui_scale", ui_scale)
	camera_pan_speed = config.get_value("gameplay", "camera_pan_speed", camera_pan_speed)
	mouse_rotate_sensitivity = config.get_value("gameplay", "mouse_rotate_sensitivity", mouse_rotate_sensitivity)
