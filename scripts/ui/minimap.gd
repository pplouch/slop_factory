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
const CAMERA_SQUARE_COLOR := Color(1, 1, 1, 0.85)

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

## Set once by World alongside set_world_bounds/set_fog_source -- lets this
## minimap re-center on the camera's own live position every frame (see
## _camera_center/_world_to_local) and draw its current ground footprint
## (see _draw_camera_square), instead of always showing a fixed view
## centered on the world origin (see feature backlog: "minimap should move
## with the camera, and camera square should be visible on the minimap").
var _camera_rig: Node3D
var _camera: Camera3D


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

## Called once by World -- see _camera_rig/_camera above.
func set_camera(camera_rig: Node3D, camera: Camera3D) -> void:
	_camera_rig = camera_rig
	_camera = camera

## The world-space point this minimap is currently centered on -- the
## camera rig's own XZ position once set_camera has run, or the world
## origin before that (matches this control's pre-camera-follow behavior,
## for the brief window before World's _ready() finishes wiring it up).
func _camera_center() -> Vector3:
	return _camera_rig.position if _camera_rig else Vector3.ZERO

## Godot per-frame hook: entity positions move every frame regardless of fog
## state, so this always redraws (FogManager.process(), called separately
## from World._process, is what actually updates fog_texture's pixels).
func _process(_delta: float) -> void:
	queue_redraw()

## World-space position -> a local pixel position within this control's rect,
## relative to the camera's current center (see _camera_center) rather than
## the world origin. Clamped to this control's own rect -- an entity outside
## the currently-shown world_half_size window still returns a point glued to
## the nearest edge rather than one further out, which is what a plain
## draw_circle(_world_to_local(pos), radius, ...) call needs: without
## `clip_contents = true` on this control (see minimap.tscn's Display node),
## a dot drawn exactly at that edge still spills `radius` pixels past the
## rect's true border, landing outside the region _draw()'s own fog overlay
## covers (which *is* confined to this rect) -- so the spilled sliver reads
## as an uncovered, never-fogged dot poking out past the minimap's edge
## (see feature request: "green dots on the minimap border are partially
## covered by fog, but not entirely, because they're partially out of the
## minimap"). clip_contents makes Godot itself discard anything drawn
## outside the rect, so the spillover is simply never rendered.
func _world_to_local(world_pos: Vector3) -> Vector2:
	var center := _camera_center()
	var nx := (world_pos.x - center.x + _world_half_size) / (_world_half_size * 2.0)
	var nz := (world_pos.z - center.z + _world_half_size) / (_world_half_size * 2.0)
	return Vector2(clamp(nx, 0.0, 1.0) * size.x, clamp(nz, 0.0, 1.0) * size.y)

## Local pixel position within this control's rect -> a world-space position
## (y always 0.0) -- the exact inverse of _world_to_local, so a click still
## resolves to the right world point regardless of where the camera has
## panned the minimap's own view to.
func _local_to_world(local_pos: Vector2) -> Vector3:
	var center := _camera_center()
	var nx := local_pos.x / size.x
	var nz := local_pos.y / size.y
	return Vector3(
		nx * _world_half_size * 2.0 - _world_half_size + center.x,
		0.0,
		nz * _world_half_size * 2.0 - _world_half_size + center.z
	)

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
		# the fog texture's (larger) own -- see _fog_world_half_size. Offset
		# by the camera's current center (not just the origin-centered span
		# the fixed-view minimap used to need) now that this minimap follows
		# the camera around the map; clamped since the camera can pan right
		# up to the fog texture's own edge.
		var center := _camera_center()
		var uv_min := Vector2(
			(_fog_world_half_size + center.x - _world_half_size) / (2.0 * _fog_world_half_size),
			(_fog_world_half_size + center.z - _world_half_size) / (2.0 * _fog_world_half_size)
		).clamp(Vector2.ZERO, Vector2.ONE)
		var uv_max := Vector2(
			(_fog_world_half_size + center.x + _world_half_size) / (2.0 * _fog_world_half_size),
			(_fog_world_half_size + center.z + _world_half_size) / (2.0 * _fog_world_half_size)
		).clamp(Vector2.ZERO, Vector2.ONE)
		var tex_size := Vector2(fog_texture.get_size())
		var source := Rect2(uv_min * tex_size, (uv_max - uv_min) * tex_size)
		draw_texture_rect_region(fog_texture, Rect2(Vector2.ZERO, size), source)
	_draw_camera_square()
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 2.0)

## Outlines the camera's current view footprint on the minimap: the 4
## corners of the actual 3D viewport, each projected onto the ground plane
## and mapped through the same _world_to_local the entity dots use, so it
## accurately reflects panning/zooming/rotation rather than being a fixed-
## size box (see feature backlog: "camera square should be visible on the
## minimap").
func _draw_camera_square() -> void:
	if _camera == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var corners := [Vector2.ZERO, Vector2(viewport_size.x, 0.0), viewport_size, Vector2(0.0, viewport_size.y)]
	var points := PackedVector2Array()
	for corner in corners:
		points.append(_world_to_local(_project_to_ground(corner)))
	points.append(points[0])
	draw_polyline(points, CAMERA_SQUARE_COLOR, 1.5)

## Ray/plane intersection of the camera's view ray through `screen_pos` with
## the y=0 ground plane -- plain geometry rather than a physics raycast
## (Minimap has no World reference to query one through), which is fine
## since CameraRig's tilt never changes, only its position/zoom/yaw.
func _project_to_ground(screen_pos: Vector2) -> Vector3:
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return from
	return from + dir * (-from.y / dir.y)
