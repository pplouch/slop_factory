class_name DebugOverlayManager
extends RefCounted
## Everything DebugMenu's buttons drive -- split out of world.gd (see
## CLAUDE.md's "world.gd -- the central controller" section). Self-contained
## relative to the other managers: reads groups (blobs/enemies/structures/
## resource_nodes) and BuildingManager/PathingManager's grid constants for
## the grid overlay, but doesn't mutate any other manager's state.

var _world: Node3D

var _debug_menu_active := false
# Whether DebugMenu's "Toggle Hitboxes" overlay (collision shapes + attack/
# detection/link ranges, attached as temporary child nodes tagged
# "debug_visual_nodes") is currently shown.
var _debug_visuals_active := false

# Whether DebugMenu's "Toggle Grid" overlay (a static line-mesh showing the
# factory-placement grid's cell boundaries) is currently shown; the overlay
# node itself is built lazily on first toggle-on, then just shown/hidden.
var _grid_overlay_active := false
var _grid_overlay: MeshInstance3D = null


func setup(world: Node3D) -> void:
	_world = world

## Signal handler for DebugMenu.toggle_requested.
func toggle_debug_menu() -> void:
	_debug_menu_active = not _debug_menu_active
	_world.debug_menu.set_active(_debug_menu_active)
	if _debug_menu_active:
		_world.close_other_ui(_world.debug_menu)

## Hides the debug panel, e.g. when another UI box opens (see
## World.close_other_ui) -- a no-op if it wasn't open to begin with.
func close_debug_menu() -> void:
	if not _debug_menu_active:
		return
	_debug_menu_active = false
	_world.debug_menu.set_active(false)

## Signal handler for DebugMenu's "Generate Blob" button: asks the nearest
## building to spawn a free blob.
func debug_spawn_blob() -> void:
	var building = _world.get_tree().get_first_node_in_group("buildings")
	if building:
		building.debug_spawn_blob()

## Every gatherable/craftable resource type in the game (see
## Effects.resource_color and Biomes' resource lists for the canonical
## names) -- used by debug_add_resources so testing build mode/the tech
## tree/the Foundry never needs an actual harvesting grind first, not just
## the original wood/stone/planks trio.
const DEBUG_RESOURCE_TYPES := [
	"wood", "stone", "planks", "knowledge", "food", "water",
	"mushroom", "cactus_fiber", "ice_crystal", "obsidian",
	"iron", "gold", "silver", "platinum", "slopium",
	"iron_bar", "gold_bar", "silver_bar", "platinum_bar", "slopium_bar",
]
const DEBUG_RESOURCE_AMOUNT := 500

## Signal handler for DebugMenu's "Add Resources" button: tops up every
## known resource type (see DEBUG_RESOURCE_TYPES) by DEBUG_RESOURCE_AMOUNT.
func debug_add_resources() -> void:
	for resource_type in DEBUG_RESOURCE_TYPES:
		GameManager.add_resource(resource_type, DEBUG_RESOURCE_AMOUNT)

## Signal handler for DebugMenu's "Show/Hide Grid" button: toggles a static
## overlay of the factory-placement grid's cell boundaries (built once, on
## first use, then just shown/hidden) -- handy while lining up belt chains.
func toggle_world_grid() -> void:
	_grid_overlay_active = not _grid_overlay_active
	_world.debug_menu.set_grid_active(_grid_overlay_active)
	if _grid_overlay_active and _grid_overlay == null:
		_grid_overlay = _build_grid_overlay()
		_world.add_child(_grid_overlay)
	if _grid_overlay:
		_grid_overlay.visible = _grid_overlay_active

## Builds a line-mesh grid spanning PathingManager.PATHING_GRID_HALF_SIZE
## (the same fixed, generous bounds the pathing grid and minimap use) at
## BuildingManager.GRID_CELL_SIZE spacing, offset by half a cell so lines
## fall on cell *boundaries* rather than through structure centers.
func _build_grid_overlay() -> MeshInstance3D:
	var half := PathingManager.PATHING_GRID_HALF_SIZE
	var cell_size := BuildingManager.GRID_CELL_SIZE
	var cell_count := int(half / cell_size)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for i in range(-cell_count, cell_count + 1):
		var offset: float = i * cell_size - cell_size * 0.5
		st.add_vertex(Vector3(offset, 0.03, -half))
		st.add_vertex(Vector3(offset, 0.03, half))
		st.add_vertex(Vector3(-half, 0.03, offset))
		st.add_vertex(Vector3(half, 0.03, offset))

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.18)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	mesh_inst.material_override = mat
	return mesh_inst

## Signal handler for DebugMenu's "Show/Hide Hitboxes" button: spawns (or
## clears) translucent collision-shape and attack/detection/link-range
## overlays on every currently-existing blob/enemy/resource node/structure.
## A one-time snapshot rather than a continuous overlay -- anything spawned
## *after* toggling on won't get one until toggled off and back on, which is
## an acceptable simplification for a debug-only tool.
func toggle_debug_visuals() -> void:
	_debug_visuals_active = not _debug_visuals_active
	_world.debug_menu.set_hitboxes_active(_debug_visuals_active)
	if _debug_visuals_active:
		_spawn_debug_visuals()
	else:
		_clear_debug_visuals()

## Attaches range-ring + collision-hitbox overlay children to every relevant
## live object. Overlays are children of their owner (so they move/rotate
## with it for free and get cleaned up automatically if the owner dies)
## rather than tracked in a separate array; _clear_debug_visuals finds them
## all again via their shared "debug_visual_nodes" group.
func _spawn_debug_visuals() -> void:
	_clear_debug_visuals()
	for blob in _world.get_tree().get_nodes_in_group("blobs"):
		_attach_range_ring(blob, blob.ATTACK_RANGE, Color(1.0, 0.3, 0.3, 0.35))
	for enemy in _world.get_tree().get_nodes_in_group("enemies"):
		_attach_range_ring(enemy, enemy.ATTACK_RANGE, Color(1.0, 0.3, 0.3, 0.35))
		_attach_range_ring(enemy, enemy.DETECTION_RANGE, Color(1.0, 0.9, 0.2, 0.2))
	for n in _world.get_tree().get_nodes_in_group("resource_nodes"):
		_attach_range_ring(n, BuildingManager.EXTRACTOR_LINK_RADIUS, Color(0.3, 1.0, 0.5, 0.18))
	for group_name in ["blobs", "enemies", "structures", "buildings"]:
		for n in _world.get_tree().get_nodes_in_group(group_name):
			_attach_hitbox_markers(n)

## Adds a flat translucent ring of the given `radius`/`color` as a child of
## `target`, used to visualize an attack/detection/link range at a glance.
func _attach_range_ring(target: Node3D, radius: float, color: Color) -> void:
	if radius <= 0.0:
		return
	var mesh_inst := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = max(radius - 0.06, 0.01)
	mesh.outer_radius = radius
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mesh.material = mat
	mesh_inst.mesh = mesh
	mesh_inst.add_to_group("debug_visual_nodes")
	target.add_child(mesh_inst)
	mesh_inst.position = Vector3(0.0, 0.05, 0.0)

## Adds a translucent wireframe-ish mesh matching each of `target`'s
## CollisionShape3D children, parented to the shape itself so its position
## automatically matches without any extra transform bookkeeping.
func _attach_hitbox_markers(target: Node3D) -> void:
	for child in target.get_children():
		if not (child is CollisionShape3D) or child.shape == null:
			continue
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 1.0, 0.2, 0.25)
		var mesh: Mesh = null
		if child.shape is SphereShape3D:
			var m := SphereMesh.new()
			m.radius = child.shape.radius
			m.height = child.shape.radius * 2.0
			mesh = m
		elif child.shape is BoxShape3D:
			var m := BoxMesh.new()
			m.size = child.shape.size
			mesh = m
		elif child.shape is CylinderShape3D:
			var m := CylinderMesh.new()
			m.top_radius = child.shape.radius
			m.bottom_radius = child.shape.radius
			m.height = child.shape.height
			mesh = m
		if mesh == null:
			continue
		mesh.material = mat
		var vis := MeshInstance3D.new()
		vis.mesh = mesh
		vis.add_to_group("debug_visual_nodes")
		child.add_child(vis)

## Removes every debug-visual overlay node, e.g. when toggling the overlay
## off or refreshing it.
func _clear_debug_visuals() -> void:
	for n in _world.get_tree().get_nodes_in_group("debug_visual_nodes"):
		if is_instance_valid(n):
			n.queue_free()
