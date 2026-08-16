extends Node3D
## Top-down RTS-style camera controller: WASD/arrow-key panning across the
## ground plane (relative to the rig's current facing, so panning still
## feels like forward/back/strafe after rotating), scroll-wheel zoom that
## slides the camera along its own fixed viewing angle, and rotation around
## the map via Q/E or a middle-mouse-button drag.
##
## Rotation and panning both use physical key codes (is_physical_key_pressed
## with KEY_Q/KEY_E/KEY_W/etc.), not the localized keycode -- physical KEY_Q
## is the key labeled "A" on an AZERTY keyboard (and physical KEY_W/KEY_A are
## labeled "Z"/"Q"), so this one binding already reads correctly as "Q/E to
## rotate, WASD to pan" on QWERTY and "A/E to rotate, ZQSD to pan" on AZERTY
## without any layout-specific branching.

const PAN_SPEED := 26.0
const ZOOM_MIN := 0.6
const ZOOM_MAX := 2.8
const ZOOM_STEP := 0.1
const BOUNDS := 68.0
const ROTATE_SPEED := 2.2  # radians/sec, keyboard-driven rotation
const MOUSE_ROTATE_SENSITIVITY := 0.006  # radians per pixel of drag

@onready var camera: Camera3D = $Camera3D

## The camera's hand-placed local offset at 100% zoom; zooming just scales
## this vector rather than recomputing an angle/distance from scratch.
var _base_offset: Vector3
var _zoom: float = 1.0
var _rotating_with_mouse := false


## Godot lifecycle hook: remembers the camera's authored offset as the
## zoom=1.0 baseline.
func _ready() -> void:
	_base_offset = camera.position

## Godot per-frame hook: reads WASD/arrow input and pans the rig across the
## XZ plane relative to its current facing (clamped to BOUNDS so the camera
## can't wander off the map), and reads Q/E for keyboard-driven rotation.
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
		var forward := -transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := transform.basis.x
		right.y = 0.0
		right = right.normalized()
		var world_move := right * move.x + forward * move.y
		position.x = clamp(position.x + world_move.x, -BOUNDS, BOUNDS)
		position.z = clamp(position.z + world_move.z, -BOUNDS, BOUNDS)

	var rotate_input := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		rotate_input += 1.0
	if Input.is_physical_key_pressed(KEY_E):
		rotate_input -= 1.0
	if rotate_input != 0.0:
		rotation.y += ROTATE_SPEED * rotate_input * delta

## Handles scroll-wheel zoom, middle-mouse-button press/release (toggles
## drag-rotation), and mouse motion while dragging (rotates the rig by the
## horizontal drag distance).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom = clamp(_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			camera.position = _base_offset * _zoom
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom = clamp(_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			camera.position = _base_offset * _zoom
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_rotating_with_mouse = event.pressed
	elif event is InputEventMouseMotion and _rotating_with_mouse:
		rotation.y -= event.relative.x * MOUSE_ROTATE_SENSITIVITY
