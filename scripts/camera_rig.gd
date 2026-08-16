extends Node3D
## Top-down RTS-style camera controller: WASD/arrow-key panning across the
## ground plane, and scroll-wheel zoom that slides the camera along its own
## fixed viewing angle rather than changing the angle itself.

const PAN_SPEED := 26.0
const ZOOM_MIN := 0.6
const ZOOM_MAX := 2.8
const ZOOM_STEP := 0.1
const BOUNDS := 68.0

@onready var camera: Camera3D = $Camera3D

## The camera's hand-placed local offset at 100% zoom; zooming just scales
## this vector rather than recomputing an angle/distance from scratch.
var _base_offset: Vector3
var _zoom: float = 1.0


## Godot lifecycle hook: remembers the camera's authored offset as the
## zoom=1.0 baseline.
func _ready() -> void:
	_base_offset = camera.position

## Godot per-frame hook: reads WASD/arrow input and pans the rig across the
## XZ plane, clamped to BOUNDS so the camera can't wander off the map.
func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		move.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if move != Vector2.ZERO:
		move = move.normalized() * PAN_SPEED * delta
		position.x = clamp(position.x + move.x, -BOUNDS, BOUNDS)
		position.z = clamp(position.z + move.y, -BOUNDS, BOUNDS)

## Handles scroll-wheel input: adjusts the zoom factor and rescales the
## camera's position along its fixed base offset (zooming in moves it
## closer to the rig's origin, zooming out moves it further away).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clamp(_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			camera.position = _base_offset * _zoom
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clamp(_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			camera.position = _base_offset * _zoom
