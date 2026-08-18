class_name LinkableBuilding
extends BuildableStructure
## Base for BuildingKinds entries meant to visually/functionally merge with
## matching neighbors along the factory grid -- Wall and BeltSegment today,
## any future grid piece with the same shape (e.g. Pipe) later. Holds what
## `refresh_connections()` used to duplicate identically in both: the
## 4-neighbor scan via GridDirections.CARDINAL_OFFSETS + World.get_structure_at,
## driven by two Template Method hooks each subclass fills in differently:
##  - `_links_to(neighbor)`: does this neighbor count as "connected"? Wall
##    only counts another Wall (a fence shouldn't visually merge into an
##    unrelated belt); the default here -- any non-null neighbor -- is
##    Belt's own behavior, reused as-is.
##  - `_set_connector_visible(key, is_visible)`: how "open toward this side"
##    actually looks. Wall shows/hides a connector bar per *world-space*
##    cardinal key; Belt shows/hides a rail per its own *rotated local* key
##    instead (see BeltSegment._world_offset_to_local_wall) -- different
##    enough to stay per-subclass rather than forced through one shared step.
##
## `blocks_movement` lets World's pathing grid ask "should this cell be
## solid" without a type check -- true (matching every other building)
## unless a subclass overrides it, which only BeltSegment does (blobs walk
## over a belt instead of routing around it).

var blocks_movement := true

## Wall/BeltSegment/Pipe/Road are numerous factory-grid pieces, not
## "buildings" in the sense BuildableStructure's own ambient-light feature
## means -- see that method's own header for why this is a plain override
## rather than the base class's default.
func _emits_ambient_light() -> bool:
	return false


## Re-checks all 4 neighboring grid cells and updates which connector/rail
## is shown toward each, via the two hooks below. Called by World once this
## structure's own placement is finalized and again whenever a structure is
## placed/demolished next to it (see World._refresh_neighbor_visuals) --
## not from this node's own _ready(), since _ready() fires synchronously
## during World's add_child(), before World has set this structure's real
## global_position/rotation.
func refresh_connections() -> void:
	var world = get_parent()
	if world == null:
		return
	var my_cell: Vector2i = world.world_to_grid(global_position)
	for key in GridDirections.CARDINAL_OFFSETS.keys():
		var neighbor: Node = world.get_structure_at(my_cell + GridDirections.CARDINAL_OFFSETS[key])
		_set_connector_visible(key, _links_to(neighbor))

## Template Method hook: default "any neighbor counts as connected" (Belt's
## behavior). Wall overrides this to only count another Wall.
func _links_to(neighbor: Node) -> bool:
	return neighbor != null

## Template Method hook: subclasses show/hide their own connector/rail node
## for cardinal `key` ("pos_x"/"neg_x"/"pos_z"/"neg_z").
func _set_connector_visible(_key: String, _is_visible: bool) -> void:
	pass


# ==============================================================================
# FAIR MULTI-SIDE INPUT -- fixes the conveyor-merge starvation bug: Godot
# processes scene children in a fixed, deterministic order, so when two
# senders both feed one shared single-slot receiver, whichever comes first in
# that order would otherwise win literally every time the slot frees, forever
# starving the other (not an occasional race -- a permanent winner, since both
# senders typically retry at the same cadence). This alternates fairly
# instead, with a grace window so a sender that stops trying altogether
# doesn't deadlock the slot for whoever's left.
# ==============================================================================

const FAIR_INPUT_GRACE_MSEC := 200

var _last_accepted_from := Vector2i.ZERO
var _other_direction_last_attempt_msec := -1

## Called from a subclass's own try_receive_input before it actually claims
## its slot (Belt now, Pipe later -- anything that accepts from more than
## one side). `slot_free` is whatever local condition means "I can accept
## right now" (Belt: `current_item == null`) -- passed in rather than
## assumed, since only the caller knows its own capacity shape.
##
## Always records the attempt, even when `slot_free` is false, so a sender
## that keeps getting rejected by a full slot still counts as "actively
## trying" once the slot does free up -- that bookkeeping is exactly what
## lets the *other* direction get first refusal at the next opening instead
## of the same winner claiming every single one.
func _resolve_fair_input(from_direction: Vector2i, slot_free: bool) -> bool:
	if from_direction != _last_accepted_from:
		_other_direction_last_attempt_msec = Time.get_ticks_msec()
	if not slot_free:
		return false
	if from_direction == _last_accepted_from and _other_direction_last_attempt_msec >= 0:
		if Time.get_ticks_msec() - _other_direction_last_attempt_msec < FAIR_INPUT_GRACE_MSEC:
			return false
	_last_accepted_from = from_direction
	return true
