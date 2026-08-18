class_name PathingManager
extends RefCounted
## Grid-based A* (AStarGrid2D) so blobs/enemies route *around* walls/
## buildings/extractors/processors instead of just locally jittering against
## them -- split out of world.gd (see CLAUDE.md's "world.gd -- the central
## controller" section). Belts stay walkable (see structure_blocks_movement),
## matching their existing "low structure, not an obstacle" design.
##
## Shares BuildingManager.GRID_CELL_SIZE (referenced directly, not
## duplicated -- see BuildingManager's header for why a single source of
## truth matters here) since the pathing grid and the factory placement grid
## must agree on cell size.

# Half-size used for the pathing grid's bounds -- not a hard map edge
# (chunks stream in however far the camera can reach), just a generous
# fixed scale, independently tuned from CameraRig.BOUNDS (see world.gd).
const PATHING_GRID_HALF_SIZE := 90.0

var _grid := AStarGrid2D.new()


## Builds the pathing grid as one big walkable plane, except deep water
## (see Biomes.is_deep_water_at), lava (Biomes.is_lava_at -- always fully
## impassable, no shallow tier), and deep oil (Biomes.is_deep_oil_at) marked
## solid upfront from terrain data rather than reactively like a placed
## structure -- units can wade the shallow border around a lake/river/oil
## pool (to gather water or build a Water Extractor, itself placement-gated
## to shallow water for the same reason: a blob has to be able to reach it
## to finish building it) but not the deep core, and never any part of a
## lava feature at all. Individual cells also go solid as blocking
## structures are placed later (see mark_cell).
func setup() -> void:
	var half := int(PATHING_GRID_HALF_SIZE / BuildingManager.GRID_CELL_SIZE)
	_grid.region = Rect2i(-half, -half, half * 2, half * 2)
	_grid.cell_size = Vector2(BuildingManager.GRID_CELL_SIZE, BuildingManager.GRID_CELL_SIZE)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	_grid.update()
	for gy in range(-half, half):
		for gx in range(-half, half):
			var world_pos := BuildingManager.grid_to_world(Vector2i(gx, gy))
			if Biomes.is_deep_water_at(world_pos.x, world_pos.z) \
					or Biomes.is_lava_at(world_pos.x, world_pos.z) \
					or Biomes.is_deep_oil_at(world_pos.x, world_pos.z):
				_grid.set_point_solid(Vector2i(gx, gy), true)

## Marks `cell` solid/clear in the pathing grid, e.g. when a wall/building is
## placed or demolished. No-ops silently if `cell` falls outside the grid's
## bounds (some structure placed right at the edge of reach).
func mark_cell(cell: Vector2i, solid: bool) -> void:
	if _grid.is_in_boundsv(cell):
		_grid.set_point_solid(cell, solid)

func is_cell_solid(cell: Vector2i) -> bool:
	return _grid.is_in_boundsv(cell) and _grid.is_point_solid(cell)

## Whether `structure` should block pathing at all -- true for anything
## without an opinion (Extractor/Processor, which never joined the tech tree
## and have no say in the matter), duck-typed against LinkableBuilding's
## `blocks_movement` property for anything that has one (Wall: true;
## BeltSegment: false, since blobs cross a belt like any other patch of
## ground rather than routing around it).
func structure_blocks_movement(structure: Node) -> bool:
	return structure.blocks_movement if "blocks_movement" in structure else true

## Computes a waypoint path (world positions) from `from` to `to` around any
## solid pathing cells in the way, or an empty array if the straight line
## between them is already clear -- callers should just walk directly toward
## `to` in that case rather than hopping through unnecessary grid-cell
## waypoints, keeping normal unobstructed movement smooth instead of visibly
## grid-snapped. Returns an empty array (meaning "just go straight and hope
## for the best") if `to` itself is out of bounds/solid, or if no path exists
## at all -- Blob's existing stall-detector/detour system is still there as a
## fallback for whatever this can't resolve.
func compute_path(from: Vector3, to: Vector3) -> Array:
	if _has_clear_line(from, to):
		return []
	var from_cell := BuildingManager.world_to_grid(from)
	var to_cell := BuildingManager.world_to_grid(to)
	if not _grid.is_in_boundsv(from_cell) or not _grid.is_in_boundsv(to_cell):
		return []
	if _grid.is_point_solid(to_cell):
		return []
	var cell_path: Array = _grid.get_id_path(from_cell, to_cell)
	var waypoints: Array = []
	for cell in cell_path:
		waypoints.append(BuildingManager.grid_to_world(cell))
	return waypoints

## Whether at least one valid route exists from `from` to `to` at all --
## either a clear straight line, or a real A*-grid path. Distinct from
## compute_path's own return value on purpose: an empty Array from
## compute_path means "already clear, no waypoints needed" in the common
## case, but AStarGrid2D.get_id_path *also* returns an empty Array when
## `to` is genuinely unreachable (e.g. fully enclosed by solid cells) --
## the two are indistinguishable from compute_path's result alone, which
## let a blob's own approach-point selection walk straight at a point it
## could never actually reach (see feature request: "unit surrounded by
## unbuilt walls... struggles to find the next building to build"). Meant
## for exactly that kind of check-before-you-commit call, not as a
## replacement for compute_path itself.
func is_reachable(from: Vector3, to: Vector3) -> bool:
	if _has_clear_line(from, to):
		return true
	var from_cell := BuildingManager.world_to_grid(from)
	var to_cell := BuildingManager.world_to_grid(to)
	if not _grid.is_in_boundsv(from_cell) or not _grid.is_in_boundsv(to_cell):
		return false
	if _grid.is_point_solid(to_cell):
		return false
	var cell_path: Array = _grid.get_id_path(from_cell, to_cell)
	return not cell_path.is_empty()

## Samples points along the straight line from `from` to `to` and checks
## whether any of them fall in a solid pathing cell -- used to skip
## grid-based pathing entirely for the common case where nothing's in the way.
func _has_clear_line(from: Vector3, to: Vector3) -> bool:
	var dist := from.distance_to(to)
	var steps := maxi(1, ceili(dist / (BuildingManager.GRID_CELL_SIZE * 0.5)))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := from.lerp(to, t)
		var cell := BuildingManager.world_to_grid(p)
		if _grid.is_in_boundsv(cell) and _grid.is_point_solid(cell):
			return false
	return true
