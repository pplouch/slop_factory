class_name ChunkManager
extends RefCounted
## Minecraft-style "generate as the camera approaches, unload once it's far
## enough away" world tiling, split out of world.gd (see CLAUDE.md's
## "world.gd -- the central controller" section for why). See
## scripts/world/chunk.gd for what a chunk actually builds and how it
## survives being unloaded and later regenerated deterministically.
##
## A plain RefCounted, not a Node -- it holds no engine callbacks of its own;
## World's own _process calls `process()` below every frame, since chunk
## streaming needs to react to the camera's current position, which only
## World (the actual scene node) can read.
##
## Unloading exists purely for memory/node-count (see feature request: "make
## sure the memory is well managed... or the game will be unplayable" -- a
## real, measured problem: CLAUDE.md's own stress-test notes ~10.6k nodes
## across 225 force-loaded chunks alone already costs meaningful framerate,
## and that number only ever grew under the old load-only design as more of
## the map got explored). Two things are deliberately never unloaded no
## matter how far away the camera gets:
## - A chunk with Chunk.has_village true (see that field's own header --
##   FriendlyVillage's trade offers are explicitly promised to stay fixed
##   for its whole lifetime, and EnemyVillage runs its own live raid-
##   cooldown/guard-respawn simulation with guards parented *under that
##   chunk*; neither is designed to survive being torn down and rebuilt from
##   scratch, and villages are rare enough that excluding their handful of
##   chunks forever costs negligible memory against the whole map).
## - A chunk any blob is currently standing in or actively travelling toward
##   (see _is_safe_to_unload) -- freeing a resource node a blob is mid-
##   harvest on, or walking toward, out from under it would leave that blob
##   holding a dangling reference update Blob's HarvestingState/MovingState
##   were never written to expect (see docs/history's own note on how those
##   states already guard against a target going away via depletion/
##   demolition -- chunk unload is the same shape, but only if it happens
##   somewhere neither state is actively watching).

const CHUNK_LOAD_RADIUS := 3
## Comfortably beyond CHUNK_LOAD_RADIUS (6 vs. 3 chunks, i.e. a full load
## radius of slack) so a camera hovering right at the load boundary doesn't
## thrash a chunk in and out of existence every check interval -- a chunk
## only unloads once it's clearly out of reach, well past where
## ensure_chunks_loaded would just regenerate it again next check anyway.
const CHUNK_UNLOAD_RADIUS := 6
const CHUNK_CHECK_INTERVAL := 0.5
## How many newly-needed chunks actually get generated per real frame once
## the camera moves and the surrounding grid changes (see process()'s own
## call to _generate_queued_chunks) -- generating a whole newly-uncovered
## row/column of chunks synchronously in one frame (each a from-scratch
## procedural ground-texture + normal-map bake, see Chunk._build_ground_material)
## was a real, measured ~0.5s freeze on every chunk-boundary crossing (see
## feature request: "moving the camera, the game freeze... make the loading
## and unloading more smooth"). Spreading that work across several frames
## instead keeps each individual frame's added cost small enough not to read
## as a stutter, at the cost of a newly-revealed chunk very briefly popping
## in a few frames later rather than instantly -- an acceptable tradeoff,
## same "safe/unnoticeable direction" this project already accepts elsewhere
## (see e.g. ResourceNode.restore_state's respawn-timer note). Unloading is
## deliberately left unthrottled: _unload_chunk is just a state snapshot plus
## queue_free(), nowhere near generation's measured cost, so there was
## nothing there worth spreading out.
const MAX_CHUNK_GENERATIONS_PER_FRAME := 1

## Chunk coordinate (Vector2i) -> the generated Chunk node there. Read
## externally by SpawnManager (picks a random already-loaded chunk to spawn
## an enemy in) -- deliberately public (no leading underscore) for that.
## SpawnManager already looks this dictionary up fresh every time it's used
## rather than caching a Chunk reference, so entries disappearing here as
## chunks unload needs no special handling on its end.
var loaded_chunks: Dictionary = {}
## Every coordinate that's ever been unloaded, mapped to its
## Chunk.snapshot_state() output -- kept for the rest of the session (never
## cleared) so a coord visited, left, and revisited any number of times
## always resumes from its last real state (see Chunk.generate's
## `saved_state` param) instead of looking freshly full/unlooted again.
var _chunk_deltas: Dictionary = {}
## Coordinates permanently excluded from _unload_far_chunks -- see this
## file's own header on why a Village pins its chunk forever.
var _pinned_coords: Dictionary = {}
## Coordinates known to still need generating, nearest-to-focus first (see
## _queue_missing_chunks) -- drained a few at a time every frame by
## _generate_queued_chunks (see MAX_CHUNK_GENERATIONS_PER_FRAME's own header
## for why). Distinct from ensure_chunks_loaded's own fully-synchronous
## behavior, which is left untouched for World's one-time scene-startup call
## and this file's test suite -- both want the whole surrounding grid ready
## immediately, not streamed in over several frames.
var _pending_coords: Array = []

var _world: Node3D
var _check_timer := 0.0


func setup(world: Node3D) -> void:
	_world = world

## Called from World._process every frame. Actually re-checks chunk coverage
## (queuing newly-needed chunks, unloading far ones) only every
## CHUNK_CHECK_INTERVAL seconds, but drains a few pending chunk generations
## every single frame regardless, so a batch queued on one check spreads
## smoothly across the many frames before the next one.
func process(delta: float, focus_position: Vector3) -> void:
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = CHUNK_CHECK_INTERVAL
		_queue_missing_chunks(focus_position)
		_unload_far_chunks(focus_position)
	_generate_queued_chunks()

## Generates every chunk within CHUNK_LOAD_RADIUS of `around_world_pos` that
## isn't already loaded. Cheap to call repeatedly -- a no-op dictionary
## lookup for every chunk that already exists, real generation work only
## for genuinely new ones.
func ensure_chunks_loaded(around_world_pos: Vector3) -> void:
	var center_coord := _world_pos_to_chunk_coord(around_world_pos)
	for dy in range(-CHUNK_LOAD_RADIUS, CHUNK_LOAD_RADIUS + 1):
		for dx in range(-CHUNK_LOAD_RADIUS, CHUNK_LOAD_RADIUS + 1):
			var coord := center_coord + Vector2i(dx, dy)
			if not loaded_chunks.has(coord):
				_generate_chunk(coord)

## Recomputes which chunks within CHUNK_LOAD_RADIUS of `around_world_pos`
## still need generating, replacing whatever was left over from the last
## check interval outright -- no point finishing a stale request for a chunk
## the focus has since moved away from again, since the very next check will
## just recompute it fresh anyway. Sorted nearest-to-focus first so
## _generate_queued_chunks's low per-frame budget always prioritizes whatever
## is closest to actually entering view.
func _queue_missing_chunks(around_world_pos: Vector3) -> void:
	var center_coord := _world_pos_to_chunk_coord(around_world_pos)
	var needed: Array = []
	for dy in range(-CHUNK_LOAD_RADIUS, CHUNK_LOAD_RADIUS + 1):
		for dx in range(-CHUNK_LOAD_RADIUS, CHUNK_LOAD_RADIUS + 1):
			var coord := center_coord + Vector2i(dx, dy)
			if not loaded_chunks.has(coord):
				needed.append(coord)
	needed.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var offset_a := a - center_coord
		var offset_b := b - center_coord
		return offset_a.x * offset_a.x + offset_a.y * offset_a.y < offset_b.x * offset_b.x + offset_b.y * offset_b.y
	)
	_pending_coords = needed

## Generates up to MAX_CHUNK_GENERATIONS_PER_FRAME chunks off the front of
## _pending_coords -- called every frame (not just every CHUNK_CHECK_INTERVAL)
## so a freshly-queued batch drains smoothly across many frames instead of
## the single frame it was queued on. Re-checks loaded_chunks per coord since
## a direct ensure_chunks_loaded call elsewhere could have generated it
## already while it sat queued here.
func _generate_queued_chunks() -> void:
	var generated := 0
	while generated < MAX_CHUNK_GENERATIONS_PER_FRAME and not _pending_coords.is_empty():
		var coord: Vector2i = _pending_coords.pop_front()
		if not loaded_chunks.has(coord):
			_generate_chunk(coord)
		generated += 1

## Frees every loaded chunk more than CHUNK_UNLOAD_RADIUS away from
## `around_world_pos`, except one pinned by _pinned_coords or one
## _is_safe_to_unload flags as still in active use. A chunk skipped this
## pass isn't queued or retried specially -- this whole function just runs
## again next CHUNK_CHECK_INTERVAL, so a chunk a blob eventually wanders (or
## finishes travelling) away from becomes eligible on its own without any
## extra bookkeeping.
func _unload_far_chunks(around_world_pos: Vector3) -> void:
	var center_coord := _world_pos_to_chunk_coord(around_world_pos)
	var to_unload: Array = []
	for coord in loaded_chunks.keys():
		if _pinned_coords.has(coord):
			continue
		var dx: int = absi(coord.x - center_coord.x)
		var dy: int = absi(coord.y - center_coord.y)
		if maxi(dx, dy) <= CHUNK_UNLOAD_RADIUS:
			continue
		if not _is_safe_to_unload(loaded_chunks[coord]):
			continue
		to_unload.append(coord)
	for coord in to_unload:
		_unload_chunk(coord)

## A chunk is unsafe to unload while any blob is currently standing inside
## it, or is still actively travelling toward a final destination inside it
## (MovingState/ReturningState, not yet arrived) -- covers both "mid-harvest
## on a resource node in there right now" and "ordered to walk to/through
## there but hasn't reached it yet" (a blob given a long Explore/patrol/move
## order can easily still be many chunks away from a far final_target).
## Every blob is checked, not just selected ones, so a whole squad
## spread-harvesting the same node all correctly veto unloading it.
func _is_safe_to_unload(chunk: Chunk) -> bool:
	var half := Chunk.CHUNK_SIZE * 0.5
	var min_pos := chunk.global_position - Vector3(half, 0.0, half)
	var max_pos := chunk.global_position + Vector3(half, 0.0, half)
	for blob in _world.get_tree().get_nodes_in_group("blobs"):
		if not is_instance_valid(blob):
			continue
		if _point_in_bounds(blob.global_position, min_pos, max_pos):
			return false
		if blob.current_state.is_travelling() and _point_in_bounds(blob.final_target, min_pos, max_pos):
			return false
	return true

func _point_in_bounds(p: Vector3, min_pos: Vector3, max_pos: Vector3) -> bool:
	return p.x >= min_pos.x and p.x <= max_pos.x and p.z >= min_pos.z and p.z <= max_pos.z

## Snapshots `coord`'s current state (see Chunk.snapshot_state) for a future
## reload, then frees the chunk node and everything under it (resource
## nodes, chest, props, particles -- see Chunk's own header for what's
## parented there).
func _unload_chunk(coord: Vector2i) -> void:
	var chunk: Chunk = loaded_chunks[coord]
	_chunk_deltas[coord] = chunk.snapshot_state()
	loaded_chunks.erase(coord)
	chunk.queue_free()

## World-space position -> the chunk coordinate containing it.
func _world_pos_to_chunk_coord(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / Chunk.CHUNK_SIZE), floori(pos.z / Chunk.CHUNK_SIZE))

## Chunk coordinate -> the world-space position of its center.
func _chunk_center_world(coord: Vector2i) -> Vector3:
	return Vector3((coord.x + 0.5) * Chunk.CHUNK_SIZE, 0.0, (coord.y + 0.5) * Chunk.CHUNK_SIZE)

## Instantiates, positions, and generates the chunk at `coord`, picking its
## biome from its world-space center (see Biomes.biome_for_world_pos) and
## handing it back whatever _unload_chunk saved for this coord last time (or
## {}, for a genuine first-time visit -- see Chunk.generate's `saved_state`).
func _generate_chunk(coord: Vector2i) -> void:
	var center := _chunk_center_world(coord)
	var biome := Biomes.biome_for_world_pos(center)
	var chunk := Chunk.new()
	_world.add_child(chunk)
	chunk.position = center
	chunk.generate(coord, biome, _chunk_deltas.get(coord, {}))
	if chunk.has_village:
		_pinned_coords[coord] = true
	loaded_chunks[coord] = chunk
