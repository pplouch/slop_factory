extends Node3D
## The player's home base: periodically spawns a free "worker" blob (scaled
## by the "growth" upgrade), pre-populates a starting crew, and lets the
## player spend wood to instantly hire a specific blob kind (see BlobKinds).
##
## Blobs actually deposit at `spawn_point`, not this node's own position --
## the building's solid collider extends well past its center, so walking
## to the center directly would mean trying to stand inside a wall.

@export var blob_scene: PackedScene = preload("res://scenes/blob.tscn")

const INITIAL_BLOB_COUNT := 3
const INITIAL_SPAWN_RADIUS := 1.2
const AUTO_SPAWN_KIND := "worker"
const BASE_SPAWN_INTERVAL := 60.0

@onready var spawn_point: Marker3D = $SpawnPoint
@onready var spawn_timer: Timer = $SpawnTimer


## Godot lifecycle hook: registers this building for lookup (by blobs
## finding "the nearest building" to deposit at), sets the spawn timer's
## current growth-upgraded duration, starts the recurring free spawn, and
## populates the starting crew.
func _ready() -> void:
	add_to_group("buildings")
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	GameManager.upgrade_changed.connect(_on_upgrade_changed)
	_apply_growth_upgrade()
	for i in INITIAL_BLOB_COUNT:
		var angle := (TAU / INITIAL_BLOB_COUNT) * i
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * INITIAL_SPAWN_RADIUS
		# Deferred: at _ready() time World (our parent) is still mid-construction
		# of its own children, so an immediate add_child here would fail.
		_spawn_blob.call_deferred(spawn_point.global_position + offset, false, AUTO_SPAWN_KIND)

## Signal handler for GameManager.upgrade_changed: only the "growth" stat
## affects this building, and only its own spawn-timer duration.
func _on_upgrade_changed(stat: String, _level: int) -> void:
	if stat == "growth":
		_apply_growth_upgrade()

## Recomputes the free-spawn timer's duration from the current "growth"
## upgrade level (higher level -> shorter wait -> blobs arrive more often).
func _apply_growth_upgrade() -> void:
	spawn_timer.wait_time = BASE_SPAWN_INTERVAL / GameManager.get_growth_multiplier()

## Signal handler for SpawnTimer: spawns one new free "worker" at a small
## random offset from the spawn point (so it doesn't land exactly on top of
## a blob that hasn't moved away yet), with the spawn-confirmation ring shown.
func _on_spawn_timer_timeout() -> void:
	var offset := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	_spawn_blob(spawn_point.global_position + offset, true, AUTO_SPAWN_KIND)

## Attempts to instantly spawn a blob of `kind_id`, paid for in wood at that
## kind's BlobKinds.hire_cost. Returns whether the purchase went through;
## BuildingMenu uses this to drive its Hire section.
func hire_blob(kind_id: String) -> bool:
	var kind = BlobKinds.get_kind(kind_id)
	if not GameManager.try_spend_wood(kind.hire_cost):
		return false
	var offset := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	_spawn_blob(spawn_point.global_position + offset, true, kind_id)
	return true

## Instantiates a blob of `kind_id` at `spawn_position`, plays its grow-in
## animation, and optionally flashes a ring marker there. `show_marker` is
## off for the initial crew (there's no "an event just happened" moment to
## call out at game start) and on for every hire or timer-driven spawn.
func _spawn_blob(spawn_position: Vector3, show_marker: bool, kind_id: String) -> void:
	var blob: Node3D = blob_scene.instantiate()
	blob.kind_id = kind_id
	get_parent().add_child(blob)
	blob.global_position = spawn_position
	blob.play_spawn_pop()

	if show_marker:
		Effects.spawn_command_marker(get_parent(), spawn_position + Vector3(0.0, 0.05, 0.0), Color(1.0, 1.0, 1.0, 1.0))
