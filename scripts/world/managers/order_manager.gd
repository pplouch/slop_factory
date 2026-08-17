class_name OrderManager
extends RefCounted
## Standing-order keyboard shortcuts (P/H/X) plus right-click order issuing
## (move/harvest/build) for the current selection -- split out of world.gd
## (see CLAUDE.md's "world.gd -- the central controller" section). Acts on
## whatever SelectionManager currently holds selected.

const MASK_GROUND := 1
const MASK_RESOURCES := 4

const COLOR_MOVE := Color(0.45, 1.0, 0.55)
const COLOR_HARVEST := Color(1.0, 0.8, 0.25)
const COLOR_PATROL := Color(0.4, 0.7, 1.0)

# A right-click harvest order spreads selected blobs across same-type nodes
# within this radius of the click, capping how many pile onto any one node
# (see TaskLock.MAX_WORKERS_PER_TARGET, shared with BuildingManager's own
# per-building cap so the two stay in sync), so a squad doesn't all crowd
# (and physically jam) a single tree.
const MAX_HARVEST_SPREAD_RADIUS := 16.0

# -- Gathering tools (see Blob.equipped_item) --
# Animals (food) and water sources are only harvestable by a blob carrying
# the matching tool -- everything else (wood/stone/mushroom/...) stays
# unrestricted, same as it always was.
const ITEM_REQUIRED_FOR_RESOURCE := {"food": "weapon", "water": "bucket"}
const EQUIP_COST := 10

# How much slack (see Blob.move_tolerance) a shared move/patrol point should
# give every blob in the current selection: solo orders get none (exact
# point, unchanged behavior), and it grows with the group size, capped, so a
# big squad doesn't leave every blob but one stuck circling the one spot
# someone else already reached.
const MOVE_TOLERANCE_PER_EXTRA_BLOB := 0.3
const MAX_MOVE_TOLERANCE := 2.5

var _world: Node3D
var _selection: SelectionManager

# Set by pressing P with blobs selected; the *next* right-click sets the
# patrol's far point instead of issuing a normal move/harvest order (see
# handle_right_click). Hold ("H") and Explore ("X") take effect immediately
# with no follow-up click needed.
var _pending_patrol := false


func setup(world: Node3D, selection: SelectionManager) -> void:
	_world = world
	_selection = selection

## Handles the standing-order keyboard shortcuts (P/H/X), no-ops if nothing
## is selected. Delegates to the same order_* methods UnitInfoPanel's
## standing-order buttons call, so keyboard and UI stay in lockstep.
func handle_order_key(keycode: int) -> void:
	if _selection.selected_blobs.is_empty():
		return
	match keycode:
		KEY_P:
			order_pending_patrol()
		KEY_H:
			order_hold()
		KEY_X:
			order_explore()

## Arms "pending patrol" for the current selection -- the *next* right-click
## sets the far point (see handle_right_click). Shared by the 'P' key and
## UnitInfoPanel's Patrol button.
func order_pending_patrol() -> void:
	if _selection.selected_blobs.is_empty():
		return
	_pending_patrol = true
	var origin: Vector3 = _selection.selected_blobs[0].global_position
	Effects.spawn_floating_text(_world, origin + Vector3(0.0, 1.6, 0.0), "Patrol: right-click far point", COLOR_PATROL)

## Orders every currently-selected blob to Hold at its own current position.
## Shared by the 'H' key and UnitInfoPanel's Hold button.
func order_hold() -> void:
	for blob in _selection.selected_blobs:
		blob.command_hold()

## Orders every currently-selected blob to Explore around its own current
## position. Shared by the 'X' key and UnitInfoPanel's Explore button.
func order_explore() -> void:
	for blob in _selection.selected_blobs:
		blob.command_explore()

## Equips every currently-selected blob that doesn't already have `item`
## ("weapon" or "bucket") with it, spending EQUIP_COST wood per blob
## actually equipped (already-equipped blobs are free, not double-charged).
## Silently does nothing if the player can't afford equipping all of them.
## Shared by UnitInfoPanel's Equip Weapon/Equip Bucket buttons.
func order_equip(item: String) -> void:
	var needing: Array = _selection.selected_blobs.filter(func(b): return b.equipped_item != item)
	if needing.is_empty():
		return
	var cost: int = EQUIP_COST * needing.size()
	if not GameManager.try_spend_wood(cost):
		return
	for blob in needing:
		blob.try_equip(item)

## Handles a right-click: does nothing if no blobs are selected, otherwise
## issues a harvest order (if a resource node was clicked) or a plain move
## order (if empty ground was clicked) to the whole selection, and spawns a
## ring marker at the target to confirm the order was accepted.
func handle_right_click(pos: Vector2) -> void:
	# A selected blob may have died (enemy combat) since it was selected;
	# drop any stale references before issuing commands to the selection.
	var prior_count := _selection.selected_blobs.size()
	_selection.selected_blobs = _selection.selected_blobs.filter(is_instance_valid)
	if _selection.selected_blobs.size() != prior_count:
		_selection.selection_changed()
	if _selection.selected_blobs.is_empty():
		return
	var hit: Dictionary = _world.raycast(pos, MASK_RESOURCES | MASK_GROUND)
	if not hit:
		return
	if _pending_patrol:
		_pending_patrol = false
		var patrol_tolerance := _group_move_tolerance()
		for blob in _selection.selected_blobs:
			blob.command_patrol(hit.position, patrol_tolerance)
		Effects.spawn_command_marker(_world, hit.position + Vector3(0.0, 0.05, 0.0), COLOR_PATROL)
		return
	var building_owner := _selection.find_building_owner(hit.collider)
	var is_under_construction: bool = building_owner != null and "is_under_construction" in building_owner and building_owner.is_under_construction
	if is_under_construction:
		_issue_build_orders(building_owner)
		Effects.spawn_command_marker(_world, building_owner.global_position + Vector3(0.0, 0.05, 0.0), COLOR_HARVEST)
	elif hit.collider.is_in_group("resource_nodes"):
		_issue_harvest_orders(hit.collider)
		Effects.spawn_command_marker(_world, hit.collider.global_position + Vector3(0.0, 0.05, 0.0), COLOR_HARVEST)
	else:
		var move_tolerance := _group_move_tolerance()
		for blob in _selection.selected_blobs:
			blob.command_move(hit.position, move_tolerance)
		Effects.spawn_command_marker(_world, hit.position + Vector3(0.0, 0.05, 0.0), COLOR_MOVE)

func _group_move_tolerance() -> float:
	return min(MAX_MOVE_TOLERANCE, max(0, _selection.selected_blobs.size() - 1) * MOVE_TOLERANCE_PER_EXTRA_BLOB)

## Assigns each selected blob to a nearby node of the same resource type as
## `clicked_node`, spreading the squad across up to TaskLock.MAX_WORKERS_PER_TARGET nodes
## within MAX_HARVEST_SPREAD_RADIUS instead of sending everyone to the exact
## node clicked. Each blob picks its own closest still-available node, and
## gets a deterministic (evenly-spaced) approach angle around it so two
## blobs assigned to the same node don't both aim for the same spot and jam
## each other. Falls back to piling everyone onto the closest candidate if
## every nearby node of that type is already at capacity.
##
## Capacity is checked via TaskLock.harvest_count -- a *live* count of every
## blob in the world currently targeting each candidate node, not a count
## scoped to just this call. A dict scoped to this call alone (the previous
## approach) had no idea a node was already fully worked by an *earlier*
## order, so a second group order issued later could still stack more than
## TaskLock.MAX_WORKERS_PER_TARGET workers onto the same node (see feature backlog:
## "units should lock a task so others pursue one that isn't locked").
func _issue_harvest_orders(clicked_node: Node) -> void:
	var target_type: String = clicked_node.resource_type
	var origin: Vector3 = clicked_node.global_position
	var tree := _world.get_tree()

	var candidates: Array = []
	for n in tree.get_nodes_in_group("resource_nodes"):
		if n.resource_type == target_type and n.global_position.distance_to(origin) <= MAX_HARVEST_SPREAD_RADIUS:
			candidates.append(n)
	if candidates.is_empty():
		candidates.append(clicked_node)

	# Animals (food) and water sources need the matching tool equipped (see
	# Blob.equipped_item) -- everything else is unrestricted. A blob missing
	# the right tool is left alone rather than silently ignored, so the
	# player understands why nothing happened.
	var required_item: String = ITEM_REQUIRED_FOR_RESOURCE.get(target_type, "")

	for blob in _selection.selected_blobs:
		if required_item != "" and blob.equipped_item != required_item:
			Effects.spawn_floating_text(_world, blob.global_position + Vector3(0.0, 1.6, 0.0), "Needs a %s!" % required_item.capitalize(), Color(1.0, 0.35, 0.3))
			continue
		var best_node: Node = null
		var best_dist := INF
		for n in candidates:
			if TaskLock.harvest_count(tree, n) >= TaskLock.MAX_WORKERS_PER_TARGET:
				continue
			var d: float = blob.global_position.distance_to(n.global_position)
			if d < best_dist:
				best_dist = d
				best_node = n
		if best_node == null:
			# Every nearby node of this type is already fully assigned; pile onto the closest one anyway.
			for n in candidates:
				var d: float = blob.global_position.distance_to(n.global_position)
				if d < best_dist:
					best_dist = d
					best_node = n
		if best_node:
			# command_harvest() below sets pending_harvest_node synchronously,
			# so this slot count (and every subsequent blob's own
			# TaskLock.harvest_count query above) already reflects it --
			# no separate running tally needed.
			var angle := (TAU / TaskLock.MAX_WORKERS_PER_TARGET) * TaskLock.harvest_count(tree, best_node)
			blob.command_harvest(best_node, angle)

## Sends every currently-selected blob to help construct `building` (any
## under-construction BuildableStructure), each with its own evenly-spaced
## approach angle around it -- the same "don't all aim for the same spot"
## trick _issue_harvest_orders uses for resource nodes -- so a squad sent to
## build doesn't jam each other trying to stand in the same place.
## Deliberately NOT capped by TaskLock.MAX_WORKERS_PER_TARGET the way
## harvest orders and BuildingManager's own auto-assign are -- the player
## explicitly right-clicked *this* building wanting it built, so honoring
## that concentrated effort takes priority over the ambient "don't crowd
## one target" rule those other two paths exist to enforce.
func _issue_build_orders(building: Node) -> void:
	var blobs := _selection.selected_blobs
	for i in blobs.size():
		var angle := (TAU / blobs.size()) * i
		blobs[i].command_build(building, angle)
