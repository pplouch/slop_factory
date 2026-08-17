class_name FogManager
extends RefCounted
## Sticky fog-of-war (revealed cells never re-hide) shared by two views that
## must always agree with each other: Minimap's 2D overlay and a flat plane
## World builds in actual 3D space to darken the ground/buildings/units the
## player hasn't explored yet. A single small Image (its alpha channel *is*
## the fog -- 1.0 unexplored, 0.0 revealed) is the one source of truth,
## exposed as `fog_texture`; both views just sample that same ImageTexture,
## so revealing a cell here updates both for free with no extra sync code.
## This used to be Minimap-only logic (a UI-only concept, "just" a visual
## mask on a 2D overview) before the 3D plane needed the identical data.
##
## Coverage is capped at `world_half_size` on every side (see World's
## FOG_HALF_SIZE) -- same fixed, generous-but-not-map-wide bound the minimap
## already lived with (independently tuned from CameraRig.BOUNDS, which is
## far larger); panning the camera outside it reaches ordinary unfogged
## terrain, matching the minimap's own existing edge-of-coverage behavior.

const FOG_RESOLUTION := 48
const VISION_RADIUS := 14.0  # world units a blob reveals around itself
## Height of the 3D fog plane above the ground -- irrelevant to draw order
## (the plane's material is no_depth_test + high render_priority, same
## trick Combatant's health bar uses to sit above a body that would
## otherwise occlude it depth-wise), just needs to clear the flattest
## terrain dip so it never visually intersects the ground mesh.
const FOG_PLANE_HEIGHT := 0.2

var world_half_size := 75.0
var fog_texture: ImageTexture

var _world: Node3D
var _fog_image: Image
var _fog_dirty := true


## Starts the fog image fully opaque (everything unexplored) and builds the
## 3D fog plane -- World reveals it over time as blobs move around, see
## process()/_reveal_around_blobs.
func setup(world: Node3D, half_size: float) -> void:
	_world = world
	world_half_size = half_size
	_fog_image = Image.create(FOG_RESOLUTION, FOG_RESOLUTION, false, Image.FORMAT_RGBA8)
	_fog_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	fog_texture = ImageTexture.create_from_image(_fog_image)
	_build_fog_plane()

## Called from World._process every frame: reveals fog around every blob and
## pushes the updated image to fog_texture only when something actually
## changed (both Minimap and the 3D fog plane read the same texture object,
## so this one update call is all either of them needs).
func process() -> void:
	_reveal_around_blobs()
	if _fog_dirty:
		fog_texture.update(_fog_image)
		_fog_dirty = false

## Reveals the fog in a circle around every currently-alive blob. Only
## blobs grant vision -- enemies are the threat being revealed, not a
## spotter -- matching the usual "fog comes from your own units" convention.
func _reveal_around_blobs() -> void:
	for blob in _world.get_tree().get_nodes_in_group("blobs"):
		if is_instance_valid(blob):
			_reveal_at(blob.global_position)

## Clears the fog's alpha (marks "explored", never re-hidden) within
## VISION_RADIUS of `world_pos`.
func _reveal_at(world_pos: Vector3) -> void:
	var center := world_to_fog_cell(world_pos)
	var cell_radius: int = ceili((VISION_RADIUS / (world_half_size * 2.0)) * FOG_RESOLUTION)
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

## Whether `world_pos` has already been revealed, or falls entirely outside
## this manager's tracked coverage (see world_half_size) where nothing is
## fogged in the first place -- used by BuildingManager to block placing
## structures somewhere the player hasn't actually seen yet (see feature
## backlog: "Player should not be able to build in the fog of war").
func is_revealed(world_pos: Vector3) -> bool:
	if absf(world_pos.x) > world_half_size or absf(world_pos.z) > world_half_size:
		return true
	var cell := world_to_fog_cell(world_pos)
	return _fog_image.get_pixel(cell.x, cell.y).a <= 0.0

## World-space position -> the fog grid cell it falls within. Public since
## it defines the exact (world_x, world_z) -> (0..1, 0..1) convention
## _build_fog_plane's hand-authored UVs must match to line the 3D mask up
## with where blobs have actually been.
func world_to_fog_cell(world_pos: Vector3) -> Vector2i:
	var nx := (world_pos.x + world_half_size) / (world_half_size * 2.0)
	var nz := (world_pos.z + world_half_size) / (world_half_size * 2.0)
	return Vector2i(
		clampi(int(nx * FOG_RESOLUTION), 0, FOG_RESOLUTION - 1),
		clampi(int(nz * FOG_RESOLUTION), 0, FOG_RESOLUTION - 1)
	)

## Builds the flat, always-on-top dark quad that masks the 3D scene wherever
## fog_texture's alpha says "unexplored". A single static plane sized to
## exactly cover world_half_size on every side -- deliberately hand-built
## (not a PlaneMesh, whose default UVs aren't guaranteed to match
## world_to_fog_cell's convention) so vertex (x, z) and UV (u, v) agree
## exactly: getting this wrong would silently offset or mirror the mask so
## it stops lining up with where blobs actually are.
func _build_fog_plane() -> void:
	var half := world_half_size
	var vertices := PackedVector3Array([
		Vector3(-half, FOG_PLANE_HEIGHT, -half),
		Vector3(half, FOG_PLANE_HEIGHT, -half),
		Vector3(half, FOG_PLANE_HEIGHT, half),
		Vector3(-half, FOG_PLANE_HEIGHT, half),
	])
	var normals := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	mat.albedo_texture = fog_texture
	mat.no_depth_test = true
	mat.render_priority = 10
	mesh.surface_set_material(0, mat)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	_world.add_child(mesh_inst)
