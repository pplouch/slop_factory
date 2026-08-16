extends Control
## Read-only top-down overview of the map: dots for blobs (the player's own
## units), enemies, resource nodes, and buildings, hand-drawn each frame via
## _draw(), composited under a sticky fog-of-war mask that only reveals
## cells once a blob has been near them and never re-hides them afterward.
##
## Deliberately a hand-drawn 2D overlay rather than a second top-down
## Camera3D rendered into a SubViewport -- far cheaper (no extra render
## pass over the 3D scene) and makes the fog mask trivial: a single small
## Image whose alpha channel *is* the fog, composited by drawing it on top
## of the dots with normal alpha blending.

## Fired when the player clicks this control -- World listens and re-centers
## the camera there. `world_pos.y` is always 0.0 (the minimap has no notion
## of terrain height); the listener is expected to only use x/z.
signal camera_move_requested(world_pos: Vector3)

const FOG_RESOLUTION := 48
const VISION_RADIUS := 14.0  # world units a blob reveals around itself
const BG_COLOR := Color(0.05, 0.09, 0.05, 0.92)
const BORDER_COLOR := Color(1, 1, 1, 0.4)

const DOT_RESOURCE := Color(0.4, 0.9, 0.4)
const DOT_BUILDING := Color(0.95, 0.85, 0.3)
const DOT_BLOB := Color(1, 1, 1)
const DOT_ENEMY := Color(1, 0.2, 0.2)

var _world_half_size := 75.0
var _fog_image: Image
var _fog_texture: ImageTexture
var _fog_dirty := true


## Godot lifecycle hook: starts the fog image fully opaque (everything
## unexplored) -- World reveals it over time as blobs move around, see
## _reveal_around_blobs.
func _ready() -> void:
	_fog_image = Image.create(FOG_RESOLUTION, FOG_RESOLUTION, false, Image.FORMAT_RGBA8)
	_fog_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	_fog_texture = ImageTexture.create_from_image(_fog_image)

## Called once by World so world-space positions map onto this control's
## rect correctly, whatever the actual map size is.
func set_world_bounds(half_size: float) -> void:
	_world_half_size = half_size

## Godot per-frame hook: reveals fog around every blob, pushes the fog
## image to its texture only when something actually changed, and redraws
## (entity positions move every frame regardless of fog state).
func _process(_delta: float) -> void:
	_reveal_around_blobs()
	if _fog_dirty:
		_fog_texture.update(_fog_image)
		_fog_dirty = false
	queue_redraw()

## Reveals the fog in a circle around every currently-alive blob. Only
## blobs grant vision -- enemies are the threat being revealed, not a
## spotter -- matching the usual "fog comes from your own units" convention.
func _reveal_around_blobs() -> void:
	for blob in get_tree().get_nodes_in_group("blobs"):
		if is_instance_valid(blob):
			_reveal_at(blob.global_position)

## Clears the fog's alpha (marks "explored", never re-hidden) within
## VISION_RADIUS of `world_pos`.
func _reveal_at(world_pos: Vector3) -> void:
	var center := _world_to_fog_cell(world_pos)
	var cell_radius: int = ceili((VISION_RADIUS / (_world_half_size * 2.0)) * FOG_RESOLUTION)
	var y0 := maxi(0, center.y - cell_radius)
	var y1 := mini(FOG_RESOLUTION - 1, center.y + cell_radius)
	var x0 := maxi(0, center.x - cell_radius)
	var x1 := mini(FOG_RESOLUTION - 1, center.x + cell_radius)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if Vector2(x, y).distance_to(Vector2(center)) > cell_radius:
				continue
			if _fog_image.get_pixel(x, y).a > 0.0:
				_fog_image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				_fog_dirty = true

## World-space position -> the fog grid cell it falls within.
func _world_to_fog_cell(world_pos: Vector3) -> Vector2i:
	var nx := (world_pos.x + _world_half_size) / (_world_half_size * 2.0)
	var nz := (world_pos.z + _world_half_size) / (_world_half_size * 2.0)
	return Vector2i(
		clampi(int(nx * FOG_RESOLUTION), 0, FOG_RESOLUTION - 1),
		clampi(int(nz * FOG_RESOLUTION), 0, FOG_RESOLUTION - 1)
	)

## World-space position -> a local pixel position within this control's rect.
func _world_to_local(world_pos: Vector3) -> Vector2:
	var nx := (world_pos.x + _world_half_size) / (_world_half_size * 2.0)
	var nz := (world_pos.z + _world_half_size) / (_world_half_size * 2.0)
	return Vector2(clamp(nx, 0.0, 1.0) * size.x, clamp(nz, 0.0, 1.0) * size.y)

## Local pixel position within this control's rect -> a world-space position
## (y always 0.0) -- the exact inverse of _world_to_local.
func _local_to_world(local_pos: Vector2) -> Vector3:
	var nx := local_pos.x / size.x
	var nz := local_pos.y / size.y
	return Vector3(nx * _world_half_size * 2.0 - _world_half_size, 0.0, nz * _world_half_size * 2.0 - _world_half_size)

## Godot input hook (Control-specific -- only fires for events actually
## inside this control's rect): a left click re-centers the camera on the
## clicked point (see World, which listens for camera_move_requested).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		camera_move_requested.emit(_local_to_world(event.position))

## Draws the background, every tracked entity as a dot, then the fog mask
## on top (its own alpha hides anything under still-unexplored cells).
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		if is_instance_valid(n):
			draw_circle(_world_to_local(n.global_position), 2.5, DOT_RESOURCE)
	for n in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(n):
			draw_circle(_world_to_local(n.global_position), 4.0, DOT_BUILDING)
	for n in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(n):
			draw_circle(_world_to_local(n.global_position), 2.5, DOT_ENEMY)
	for n in get_tree().get_nodes_in_group("blobs"):
		if is_instance_valid(n):
			draw_circle(_world_to_local(n.global_position), 2.5, DOT_BLOB)
	draw_texture_rect(_fog_texture, Rect2(Vector2.ZERO, size), false)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 2.0)
