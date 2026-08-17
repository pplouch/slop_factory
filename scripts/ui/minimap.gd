extends Control
## Read-only top-down overview of the map: dots for blobs (the player's own
## units), enemies, resource nodes, and buildings, hand-drawn each frame via
## _draw(), composited under a sticky fog-of-war mask that only reveals
## cells once a blob has been near them and never re-hides them afterward.
##
## Deliberately a hand-drawn 2D overlay rather than a second top-down
## Camera3D rendered into a SubViewport -- far cheaper (no extra render
## pass over the 3D scene) and makes the fog mask trivial: just draw
## `fog_texture` on top of the dots with normal alpha blending. The fog
## data itself (the Image/texture, the reveal-around-blobs logic) now lives
## in FogManager, not here -- World's main 3D view also masks itself with
## the very same fog_texture (a flat plane FogManager builds), so this
## control just needs a reference to it, set externally via World, rather
## than owning fog state a second time.

## Fired when the player clicks this control -- World listens and re-centers
## the camera there. `world_pos.y` is always 0.0 (the minimap has no notion
## of terrain height); the listener is expected to only use x/z.
signal camera_move_requested(world_pos: Vector3)

const BG_COLOR := Color(0.05, 0.09, 0.05, 0.92)
const BORDER_COLOR := Color(1, 1, 1, 0.4)

const DOT_RESOURCE := Color(0.4, 0.9, 0.4)
const DOT_BUILDING := Color(0.95, 0.85, 0.3)
const DOT_BLOB := Color(1, 1, 1)
const DOT_ENEMY := Color(1, 0.2, 0.2)

## Set externally by World right after FogManager.setup() (see
## set_fog_source) -- null for the brief window before that, so _draw()
## guards against it.
var fog_texture: ImageTexture
## The fog texture's *own* world half-size (FogManager.world_half_size),
## independent of and generally much larger than this minimap's own
## _world_half_size below -- a minimap is deliberately a local overview,
## while fog now covers as far as the camera can ever pan (see feature
## backlog 3: fog used to share this minimap's own bound and only covered
## a small area). _draw() crops fog_texture down to just the sub-region
## this minimap actually shows rather than stretching the whole (much
## larger) texture across its rect, which would make the small revealed
## area near the player shrink to a speck.
var _fog_world_half_size := 90.0

var _world_half_size := 75.0


## Called once by World so world-space positions map onto this control's
## rect correctly, whatever the actual map size is.
func set_world_bounds(half_size: float) -> void:
	_world_half_size = half_size

## Called once by World right after FogManager.setup() -- `texture` is the
## shared fog ImageTexture, `fog_half_size` is the world half-size *that
## texture* covers (see _fog_world_half_size).
func set_fog_source(texture: ImageTexture, fog_half_size: float) -> void:
	fog_texture = texture
	_fog_world_half_size = fog_half_size

## Godot per-frame hook: entity positions move every frame regardless of fog
## state, so this always redraws (FogManager.process(), called separately
## from World._process, is what actually updates fog_texture's pixels).
func _process(_delta: float) -> void:
	queue_redraw()

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
	if fog_texture:
		# UV span of this minimap's own (smaller) world_half_size within
		# the fog texture's (larger) own -- see _fog_world_half_size.
		var uv_min: float = (_fog_world_half_size - _world_half_size) / (2.0 * _fog_world_half_size)
		var uv_max: float = (_fog_world_half_size + _world_half_size) / (2.0 * _fog_world_half_size)
		var tex_size := Vector2(fog_texture.get_size())
		var source := Rect2(Vector2(uv_min, uv_min) * tex_size, Vector2(uv_max - uv_min, uv_max - uv_min) * tex_size)
		draw_texture_rect_region(fog_texture, Rect2(Vector2.ZERO, size), source)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 2.0)
