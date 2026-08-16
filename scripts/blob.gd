extends Combatant
## A single worker unit: walks where it's told, harvests resource nodes,
## carries the yield home, hands it off to GameManager's stockpile, and
## defends itself if an enemy gets close.
##
## Design patterns in play here:
## - State (see scripts/blob_states/): `current_state` holds one of
##   IdleState / MovingState / HarvestingState / ReturningState, and
##   `_physics_process` just forwards to whichever is active. This file
##   still owns all the *shared* mechanics each state calls into (movement,
##   stall recovery, inventory, stats) -- the states only hold the
##   branching logic for "what should happen this frame in this phase".
## - Factory (scripts/effects.gd): all particle/floating-text/marker
##   creation is delegated to the Effects autoload instead of instantiating
##   scenes by hand here.
## - Inheritance (scripts/combatant.gd): health/damage/regen math lives once
##   in the shared Combatant base; this file only adds blob-specific attack
##   behavior (who to hit, how hard, how often).
##
## Combat here is deliberately passive: a blob keeps doing its job (walking,
## harvesting) and will auto-swing at any enemy that comes within
## ATTACK_RANGE, but never goes looking for a fight or interrupts its task
## to chase one down.

# -- Tunable stats (base values; see _refresh_stats for how upgrades and
# -- blob-kind multipliers combine to scale them) --
const BASE_SPEED := 3.2
const BASE_CARRY_CAPACITY := 10
const BASE_HARVEST_AMOUNT := 1
const BASE_HARVEST_INTERVAL := 1.0
const BASE_ATTACK_POWER := 2.0
const BASE_ATTACK_INTERVAL := 1.0
const BASE_DEXTERITY := 1.0
const BASE_MAX_HEALTH := 20.0
const BASE_HEALTH_REGEN := 0.4
const ARRIVE_DISTANCE := 0.4
const APPROACH_RADIUS := 1.15
const ATTACK_RANGE := 1.3

# -- Stall recovery tuning (see _update_stall_detection / _start_detour) --
const PROGRESS_CHECK_INTERVAL := 0.25
const MIN_PROGRESS_DISTANCE := 0.2
const STALL_STRIKES_TO_DETOUR := 2
const DETOUR_DURATION := 1.0
const DETOUR_SIDE_DISTANCE := 2.0

const SELECTED_COLOR := Color(1.0, 0.95, 0.3, 1)
const HOVER_COLOR := Color(0.85, 0.9, 1.0, 1)
const DEPOSIT_COLOR := Color(1.0, 0.92, 0.5)

@onready var visuals: Node3D = $Visuals
@onready var selection_ring: MeshInstance3D = $Visuals/SelectionRing
@onready var body_mesh: MeshInstance3D = $Visuals/Body

## Which BlobKinds archetype this blob is. Must be set (by whoever
## instantiates the scene, e.g. Building) *before* this node enters the
## tree, since _ready() reads it immediately to pick stats and cosmetics.
@export var kind_id: String = "worker"

# Stats: base values scaled by both building upgrades and this blob's kind,
# refreshed live so a purchase affects blobs already out in the field, not
# just future ones. (health/max_health/dexterity/health_regen live on the
# Combatant base class.)
var speed: float = BASE_SPEED
var carry_capacity: int = BASE_CARRY_CAPACITY
var harvest_amount: int = BASE_HARVEST_AMOUNT
var harvest_interval: float = BASE_HARVEST_INTERVAL
var attack_power: float = BASE_ATTACK_POWER
var attack_interval: float = BASE_ATTACK_INTERVAL

var _kind_scale: float = 1.0
var _attack_cooldown: float = 0.0

## Resource type -> amount currently being carried. Normally holds at most
## one key at a time (a blob only harvests one node at a once), but it's a
## real dictionary rather than a single (type, amount) pair so a future
## "mixed loot" pickup wouldn't need a data-model change.
var inventory: Dictionary = {}

## The active State-pattern object; see scripts/blob_states/blob_state.gd.
var current_state: BlobState

## Where MovingState/ReturningState are steering toward *right now* -- may
## be a temporary detour waypoint, see _update_stall_detection.
var move_target: Vector3 = Vector3.ZERO
## The real destination arrival is measured against (never a detour point).
var final_target: Vector3 = Vector3.ZERO
## The resource node this blob is walking to / currently harvesting, if any.
var pending_harvest_node: Node = null

var _approach_angle: float = 0.0
var _detour_timer: float = 0.0
var _progress_check_timer: float = 0.0
var _progress_check_origin: Vector3 = Vector3.ZERO
var _stall_strikes: int = 0
var _consecutive_detours: int = 0
var _ring_material: StandardMaterial3D
var _selected := false
var _hovered := false


## Godot lifecycle hook: wires up the blob's group membership, cosmetics,
## starting stats/health and state, then starts its idle breathing animation.
func _ready() -> void:
	add_to_group("blobs")
	_apply_kind_look()
	_ring_material = selection_ring.mesh.material.duplicate()
	selection_ring.set_surface_override_material(0, _ring_material)
	_refresh_stats()
	health = max_health
	GameManager.upgrade_changed.connect(_on_upgrade_changed)
	_transition_to(IdleState.new())
	_start_idle_bob()

## Kicks off a looping, never-ending tween that gently bobs the blob's
## visuals up and down, purely for charm -- makes it read as "alive" even
## while standing still.
func _start_idle_bob() -> void:
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(visuals, "position:y", 0.08, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(visuals, "position:y", 0.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Signal handler for GameManager.upgrade_changed: any upgrade purchase
## (by anyone, for any stat) just recomputes this blob's stats from scratch.
func _on_upgrade_changed(_stat: String, _level: int) -> void:
	_refresh_stats()

## Recomputes every stat (including combat ones) from GameManager's current
## upgrade levels layered with this blob's kind multipliers. Called on
## startup and whenever an upgrade is purchased. Health is clamped rather
## than reset, so a purchase never fully heals a hurt blob as a side effect.
func _refresh_stats() -> void:
	var kind := BlobKinds.get_kind(kind_id)
	speed = BASE_SPEED * GameManager.get_speed_multiplier() * kind.speed_mult
	carry_capacity = max(1, int(round((BASE_CARRY_CAPACITY + GameManager.get_capacity_bonus()) * kind.capacity_mult)))
	harvest_amount = max(1, int(round(BASE_HARVEST_AMOUNT * GameManager.get_strength_multiplier() * kind.harvest_mult)))
	harvest_interval = BASE_HARVEST_INTERVAL / GameManager.get_efficiency_multiplier()

	attack_power = BASE_ATTACK_POWER * GameManager.get_strength_multiplier() * kind.harvest_mult
	attack_interval = BASE_ATTACK_INTERVAL / kind.speed_mult
	dexterity = BASE_DEXTERITY * kind.speed_mult
	health_regen = BASE_HEALTH_REGEN
	max_health = max(1.0, BASE_MAX_HEALTH * kind.capacity_mult)
	health = min(health, max_health)

## Colors and sizes this blob according to its BlobKinds archetype (a
## per-instance hue jitter keeps same-kind blobs distinguishable from each
## other while still clearly belonging to the same family). Duplicates the
## shared sphere material first so this doesn't recolor every other blob
## using the same mesh resource.
func _apply_kind_look() -> void:
	var kind := BlobKinds.get_kind(kind_id)
	_kind_scale = kind.body_scale

	var mat: StandardMaterial3D = body_mesh.mesh.material.duplicate()
	var hue := fposmod(kind.hue + randf_range(-0.03, 0.03), 1.0)
	mat.albedo_color = Color.from_hsv(hue, kind.saturation, kind.value)
	body_mesh.set_surface_override_material(0, mat)

	visuals.scale = Vector3.ONE * _kind_scale

## Plays a "pop into existence" grow-in animation, used when a blob first
## spawns at the building. Scales only the cosmetic Visuals node, never the
## physics body itself (a CharacterBody3D scaled to zero produces a
## degenerate transform Jolt can't simulate correctly).
func play_spawn_pop() -> void:
	visuals.scale = Vector3.ZERO
	var tween := create_tween()
	tween.tween_property(visuals, "scale", Vector3.ONE * _kind_scale, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Called by World when this blob is added to / removed from the current
## selection. Toggles the selection ring on.
func set_selected(value: bool) -> void:
	_selected = value
	_update_ring()

## Called by World when the mouse starts/stops hovering this blob (while
## nothing is being dragged). Toggles a dimmer version of the ring so an
## unselected blob still reads as "clickable".
func set_hovered(value: bool) -> void:
	_hovered = value
	_update_ring()

## Applies the current selected/hovered flags to the ring's visibility and
## color. Selected always wins over merely-hovered when both are true.
func _update_ring() -> void:
	selection_ring.visible = _selected or _hovered
	var color: Color = SELECTED_COLOR if _selected else HOVER_COLOR
	_ring_material.albedo_color = color
	_ring_material.emission = color

## Player order: walk to `target` and stop (no follow-up task). Cancels any
## harvest job this blob was working on.
func command_move(target: Vector3) -> void:
	pending_harvest_node = null
	_set_destination(target)
	_transition_to(MovingState.new())
	_acknowledge_order()

## Player order: walk to (an approach point around) `node` and start
## harvesting it on arrival. `approach_angle` lets World spread multiple
## blobs evenly around a shared node instead of them all aiming for the
## same spot; omit it to pick a random angle (used for solo orders).
func command_harvest(node: Node, approach_angle: float = -1.0) -> void:
	pending_harvest_node = node
	_approach_angle = approach_angle if approach_angle >= 0.0 else randf() * TAU
	_set_destination(_approach_point(node.global_position, _approach_angle))
	_transition_to(MovingState.new())
	_acknowledge_order()

## Switches the state machine to `next_state`, calling exit/enter hooks on
## the outgoing/incoming states so they can do one-time setup/teardown.
func _transition_to(next_state: BlobState) -> void:
	if current_state:
		current_state.exit(self)
	current_state = next_state
	current_state.enter(self)

## Points the blob at a new destination and resets everything the
## stall-detector uses to measure "am I making progress", so a fresh order
## never inherits stale progress-tracking state from the previous one.
func _set_destination(target: Vector3) -> void:
	final_target = target
	move_target = target
	_detour_timer = 0.0
	_stall_strikes = 0
	_progress_check_timer = 0.0
	_progress_check_origin = global_position

## Picks a point `APPROACH_RADIUS` from `target` at `angle` (plus a small
## random jitter so a group of blobs doesn't look perfectly geometric),
## used as the actual walk-to point for a harvest order -- blobs stand next
## to a resource node's edge rather than trying to walk into its center.
func _approach_point(target: Vector3, angle: float) -> Vector3:
	var jittered_angle := angle + randf_range(-0.15, 0.15)
	return target + Vector3(cos(jittered_angle), 0.0, sin(jittered_angle)) * APPROACH_RADIUS

## Plays a quick squash-and-recover animation on the body, giving visible
## feedback the instant an order is accepted (in addition to the ring
## marker World spawns at the target).
func _acknowledge_order() -> void:
	body_mesh.scale = Vector3(1.15, 0.65, 1.15)
	var tween := create_tween()
	tween.tween_property(body_mesh, "scale", Vector3(1, 0.85, 1), 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Godot physics tick: delegates all state-specific behavior to
## `current_state`, then runs the bookkeeping that applies regardless of
## state (actually moving the physics body, keeping it pinned to the
## ground plane, watching for stalls, and defending against nearby enemies).
func _physics_process(delta: float) -> void:
	var next_state := current_state.physics_update(self, delta)
	if next_state:
		_transition_to(next_state)
	move_and_slide()
	# This game has no vertical gameplay; clamp out any drift physics
	# resolution might introduce (e.g. from being wedged between several
	# other bodies) so blobs never sink into or climb out of the ground.
	global_position.y = 0.0
	_update_stall_detection(delta)
	_update_combat(delta)

## Moves the blob toward `target` at its current speed and faces it that
## direction. Shared by MovingState and ReturningState.
func _step_toward(target: Vector3) -> void:
	var to_target := target - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance <= 0.05:
		velocity = Vector3.ZERO
		return
	var direction := to_target / distance
	velocity = direction * speed
	look_at(global_position + direction, Vector3.UP)

## Watches for a blob that's supposed to be travelling but isn't actually
## getting anywhere -- e.g. wedged against an obstacle it's approaching
## nearly head-on, where physics sliding alone can't route it around. Rather
## than trust `velocity` (which can stay at its input value even while the
## body is fully blocked), this tracks real displacement over a short
## rolling window and, after enough stalled checks in a row, kicks off a
## sideways detour (see _start_detour).
func _update_stall_detection(delta: float) -> void:
	if not current_state.is_travelling():
		_stall_strikes = 0
		_progress_check_timer = 0.0
		_detour_timer = 0.0
		return

	# While a detour waypoint is active, count down until it expires (or
	# we've effectively reached it), then resume heading for the real target.
	if _detour_timer > 0.0:
		_detour_timer -= delta
		if _detour_timer <= 0.0 or global_position.distance_to(move_target) < 0.4:
			move_target = final_target

	_progress_check_timer += delta
	if _progress_check_timer < PROGRESS_CHECK_INTERVAL:
		return

	var progress := global_position.distance_to(_progress_check_origin)
	_progress_check_timer = 0.0
	_progress_check_origin = global_position

	if progress < MIN_PROGRESS_DISTANCE:
		_stall_strikes += 1
		if _stall_strikes >= STALL_STRIKES_TO_DETOUR and _detour_timer <= 0.0:
			_start_detour()
			_stall_strikes = 0
	else:
		_stall_strikes = 0
		_consecutive_detours = 0

## Redirects the blob to a temporary waypoint off to one side of its path,
## to break a head-on stall against an obstacle. Each detour attempt that
## doesn't resolve the stall (tracked via _consecutive_detours) escalates
## the distance and duration of the next one, in case the first nudge
## wasn't enough to clear whatever it's stuck on.
func _start_detour() -> void:
	var to_target := final_target - global_position
	to_target.y = 0.0
	if to_target.length() < 0.01:
		return
	_consecutive_detours += 1
	var escalation: float = 1.0 + min(_consecutive_detours, 4) * 0.6
	var dir := to_target.normalized()
	var side := Vector3(-dir.z, 0.0, dir.x) * (1.0 if randf() < 0.5 else -1.0)
	move_target = global_position + side * DETOUR_SIDE_DISTANCE * escalation + dir * 1.0
	_detour_timer = DETOUR_DURATION * escalation

## Called by HarvestingState once its inventory is full or the node is
## dry: finds the nearest building and heads for its SpawnPoint (an open
## spot just outside the building's solid walls -- walking to the
## building's own center would mean trying to stand inside a solid wall,
## which is unreachable and would strand the blob).
func _start_returning_trip() -> BlobState:
	var building := _find_nearest_building()
	if building:
		_set_destination(building.spawn_point.global_position)
		return ReturningState.new()
	return IdleState.new()

## Called by ReturningState on arrival at the building: hands the whole
## inventory over to GameManager's stockpile, then either loops back to
## harvest the same node again (if it still has resources) or goes idle.
func _deposit() -> BlobState:
	if _inventory_total() > 0:
		Effects.spawn_impact(get_parent(), global_position + Vector3(0.0, 0.7, 0.0), DEPOSIT_COLOR, 12)
	for resource_type in inventory.keys():
		GameManager.add_resource(resource_type, inventory[resource_type])
	_clear_inventory()

	if is_instance_valid(pending_harvest_node) and pending_harvest_node.amount > 0:
		_set_destination(_approach_point(pending_harvest_node.global_position, _approach_angle))
		return MovingState.new()
	pending_harvest_node = null
	return IdleState.new()

## Called by HarvestingState each time a harvest tick actually yields
## something: records it in the inventory and fires the pickup feedback
## (floating "+N" text and a small particle puff at the resource node).
func _collect(resource_type: String, amount: int, source_pos: Vector3) -> void:
	_add_to_inventory(resource_type, amount)
	var color := Effects.resource_color(resource_type)
	var text_pos := global_position + Vector3(randf_range(-0.15, 0.15), 1.15, randf_range(-0.15, 0.15))
	Effects.spawn_floating_text(get_parent(), text_pos, "+%d" % amount, color)
	Effects.spawn_impact(get_parent(), source_pos + Vector3(0.0, 0.6, 0.0), color, 6)

## Sum of every resource type currently held, compared against
## `carry_capacity` to decide when a blob's inventory is "full".
func _inventory_total() -> int:
	var total := 0
	for amount in inventory.values():
		total += amount
	return total

## Adds `amount` of `resource_type` to the inventory (no-op for amount <= 0,
## since harvest() can legitimately return 0 on the last depleting tick).
func _add_to_inventory(resource_type: String, amount: int) -> void:
	if amount <= 0:
		return
	inventory[resource_type] = inventory.get(resource_type, 0) + amount

## Empties the inventory after a successful deposit.
func _clear_inventory() -> void:
	inventory.clear()

## Auto-defense: on a cooldown independent of whatever job this blob is
## doing, swings at the nearest enemy within ATTACK_RANGE if there is one.
## Deliberately reactive rather than proactive -- see the file header.
func _update_combat(delta: float) -> void:
	_attack_cooldown = max(0.0, _attack_cooldown - delta)
	var enemy := _find_nearest_enemy_in_range(ATTACK_RANGE)
	if enemy:
		_note_combat_activity()
		if _attack_cooldown <= 0.0:
			_attack_cooldown = attack_interval
			enemy.take_damage(attack_power, self)
	_update_combat_regen(delta)

## Closest member of the "enemies" group within `range`, or null.
func _find_nearest_enemy_in_range(range_limit: float) -> Node:
	var nearest: Node = null
	var nearest_dist := range_limit
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var d := global_position.distance_to(enemy.global_position)
		if d <= nearest_dist:
			nearest_dist = d
			nearest = enemy
	return nearest

## Finds the closest building in the "buildings" group, used both to decide
## where to deposit and (implicitly) to support multiple buildings later
## without any of this logic needing to change.
func _find_nearest_building() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist := INF
	for building in get_tree().get_nodes_in_group("buildings"):
		var d := global_position.distance_to(building.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = building
	return nearest
