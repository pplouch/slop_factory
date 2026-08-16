extends Node3D
## The player's home base -- built via Build Mode, not present at game start
## (see World's founder blobs for what the player starts with instead).
## Periodically spawns a free "worker" blob (scaled by the "growth"
## upgrade and this building's own upgrade_level), lets the player spend
## wood to instantly hire a specific blob kind (see BlobKinds), and accepts
## resources delivered by belts through its input ports (see BuildingKinds
## for this building's port layout).
##
## Blobs actually deposit at `spawn_point`, not this node's own position --
## the building's solid collider extends well past its center, so walking
## to the center directly would mean trying to stand inside a wall.

@export var blob_scene: PackedScene = preload("res://scenes/blob.tscn")

## Which BuildingKinds entry this instance is -- set by World at placement
## time, before this node enters the tree. Used to look up display name,
## durability, and per-level upgrade costs/perks for BuildingMenu's
## generic "This Building" info section.
@export var kind_id: String = "town_hall"

const AUTO_SPAWN_KIND := "worker"
const BASE_SPAWN_INTERVAL := 60.0
## Fraction shaved off the spawn interval per upgrade level (levels 1-2;
## level 3's perk is qualitative -- see _on_spawn_timer_timeout).
const SPAWN_INTERVAL_REDUCTION_PER_LEVEL := 0.15
const HIRE_COST_REDUCTION_AT_LEVEL_2 := 0.1

## Per-instance upgrade progress (0..BuildingKinds.get_kind(kind_id).upgrade_costs.size()),
## bought via BuildingMenu's "This Building" section -- distinct from
## GameManager's account-wide upgrades (speed/strength/...), which apply to
## every blob regardless of which building is open.
var upgrade_level := 0
var durability: int
var max_durability: int

@onready var spawn_point: Marker3D = $SpawnPoint
@onready var spawn_timer: Timer = $SpawnTimer


## Godot lifecycle hook: registers this building for lookup (by blobs
## finding "the nearest building" to deposit at), sets durability from its
## BuildingKinds entry, and starts the recurring free spawn at its current
## growth+upgrade-adjusted duration.
func _ready() -> void:
	add_to_group("buildings")
	var kind := BuildingKinds.get_kind(kind_id)
	max_durability = kind.max_durability
	durability = max_durability
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	GameManager.upgrade_changed.connect(_on_upgrade_changed)
	_apply_growth_upgrade()

## Signal handler for GameManager.upgrade_changed: only the "growth" stat
## affects this building, and only its own spawn-timer duration.
func _on_upgrade_changed(stat: String, _level: int) -> void:
	if stat == "growth":
		_apply_growth_upgrade()

## Recomputes the free-spawn timer's duration from the current "growth"
## upgrade level (higher level -> shorter wait -> blobs arrive more often)
## layered with this building's own per-instance upgrade_level (levels 1-2
## each shave another SPAWN_INTERVAL_REDUCTION_PER_LEVEL off).
func _apply_growth_upgrade() -> void:
	var level_reduction: float = 1.0 - min(upgrade_level, 2) * SPAWN_INTERVAL_REDUCTION_PER_LEVEL
	spawn_timer.wait_time = (BASE_SPAWN_INTERVAL / GameManager.get_growth_multiplier()) * level_reduction

## Attempts to spend this building's next upgrade level's wood cost (see
## BuildingKinds.upgrade_costs). Returns whether it went through; the
## caller (BuildingMenu) is responsible for refreshing its own display.
func try_upgrade() -> bool:
	var kind := BuildingKinds.get_kind(kind_id)
	if upgrade_level >= kind.upgrade_costs.size():
		return false
	if not GameManager.try_spend_wood(kind.upgrade_costs[upgrade_level]):
		return false
	upgrade_level += 1
	_apply_growth_upgrade()
	return true

## Signal handler for SpawnTimer: spawns one new free blob at a small
## random offset from the spawn point (so it doesn't land exactly on top of
## a blob that hasn't moved away yet), with the spawn-confirmation ring
## shown. Level 3's perk swaps the always-"worker" default for a random
## kind, a small qualitative bonus rather than another numeric tweak.
func _on_spawn_timer_timeout() -> void:
	var offset := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	var kind_to_spawn := AUTO_SPAWN_KIND
	if upgrade_level >= 3:
		kind_to_spawn = BlobKinds.get_ordered_ids().pick_random()
	_spawn_blob(spawn_point.global_position + offset, true, kind_to_spawn)

## Attempts to instantly spawn a blob of `blob_kind_id`, paid for in wood at
## that kind's BlobKinds.hire_cost (discounted 10% once this building has
## reached upgrade level 2). Returns whether the purchase went through;
## BuildingMenu uses this to drive its Hire section.
func hire_blob(blob_kind_id: String) -> bool:
	var kind = BlobKinds.get_kind(blob_kind_id)
	var cost: int = kind.hire_cost
	if upgrade_level >= 2:
		cost = int(round(cost * (1.0 - HIRE_COST_REDUCTION_AT_LEVEL_2)))
	if not GameManager.try_spend_wood(cost):
		return false
	var offset := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	_spawn_blob(spawn_point.global_position + offset, true, blob_kind_id)
	return true

## Debug-only: spawns a free blob of a random kind, bypassing the wood
## cost. Used by DebugMenu's "Generate Blob" button.
func debug_spawn_blob() -> void:
	var offset := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	var blob_kind_id: String = BlobKinds.get_ordered_ids().pick_random()
	_spawn_blob(spawn_point.global_position + offset, true, blob_kind_id)

## Instantiates a blob of `blob_kind_id` at `spawn_position`, plays its
## grow-in animation, and flashes a ring marker there (`show_marker` exists
## so a future silent/bulk spawn path could suppress it, though every
## current caller wants it on).
func _spawn_blob(spawn_position: Vector3, show_marker: bool, blob_kind_id: String) -> void:
	var blob: Node3D = blob_scene.instantiate()
	blob.kind_id = blob_kind_id
	get_parent().add_child(blob)
	blob.global_position = spawn_position
	blob.play_spawn_pop()

	if show_marker:
		Effects.spawn_command_marker(get_parent(), spawn_position + Vector3(0.0, 0.05, 0.0), Color(1.0, 1.0, 1.0, 1.0))

## Accepts any resource type delivered via an input-port belt (see
## BuildingKinds' input_ports for which grid cells World registers as this
## building's ports), straight into the stockpile -- the Town Hall doesn't
## process anything, it's the final destination. `_from_direction` is
## unused but kept for interface consistency with BeltSegment/Processor.
func try_receive_input(item: Node3D, _from_direction: Vector2i = Vector2i.ZERO) -> bool:
	GameManager.add_resource(item.resource_type, item.amount)
	Effects.spawn_impact(get_parent(), item.global_position + Vector3(0.0, 0.3, 0.0), Effects.resource_color(item.resource_type), 4)
	item.queue_free()
	return true
