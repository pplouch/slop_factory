class_name EnemyVillage
extends StaticBody3D
## An unfriendly outpost scattered across the map (see
## Chunk._maybe_spawn_village), guarded by a small band of Enemy instances
## spawned around it. The player must defeat every guard before it can be
## raided -- clicking it while still guarded just warns instead of opening
## anything, since there's nothing to choose yet, only "can I loot this."
## Once undefended, clicking it steals its whole loot table at once (see
## Chest.open, the same one-shot-grant shape) and starts a cooldown before
## fresh guards and a fresh loot roll bring it back up, so a raided village
## is a repeatable target rather than a one-time chest.

const GUARD_COUNT := 3
const GUARD_SPAWN_RADIUS := 2.5
const RAID_COOLDOWN := 60.0

## Loot pool is deliberately richer than Chest's own (bigger amounts, higher
## rare chance) -- stealing from a guarded village is meant to read as a
## bigger risk/reward than picking up an unguarded chest.
const COMMON_LOOT := ["wood", "stone", "planks"]
const RARE_LOOT := ["iron", "gold", "silver", "platinum", "slopium", "knowledge"]
const RARE_CHANCE := 0.5
const COMMON_AMOUNT_RANGE := Vector2i(30, 80)
const RARE_AMOUNT_RANGE := Vector2i(10, 30)

const WARNING_COLOR := Color(1.0, 0.3, 0.25)
const LOOT_COLOR := Color(1.0, 0.85, 0.3)

## This raid cycle's rolled loot, generated fresh by _ready/_respawn.
var loot: Dictionary = {}
var _guards: Array = []
var _looted := false
var _respawn_elapsed := 0.0


## Godot lifecycle hook: makes this village discoverable/clickable (see
## SelectionManager.handle_click_select), rolls its first loot table, and
## spawns its initial guard band.
func _ready() -> void:
	add_to_group("enemy_villages")
	loot = _roll_loot()
	_spawn_guards()

## Godot per-frame hook: once looted, counts down RAID_COOLDOWN before
## bringing the village back up with fresh guards and loot.
func _process(delta: float) -> void:
	if not _looted:
		return
	_respawn_elapsed += delta
	if _respawn_elapsed >= RAID_COOLDOWN:
		_respawn()

## Rolls a random haul: 1-2 common resource types, plus a RARE_CHANCE
## chance of one additional rare bonus type (see Chest._roll_loot, the same
## shape with richer ranges/odds -- see class doc for why).
func _roll_loot() -> Dictionary:
	var result: Dictionary = {}
	var pool := COMMON_LOOT.duplicate()
	pool.shuffle()
	var common_count := randi_range(1, 2)
	for i in min(common_count, pool.size()):
		result[pool[i]] = randi_range(COMMON_AMOUNT_RANGE.x, COMMON_AMOUNT_RANGE.y)
	if randf() < RARE_CHANCE:
		var rare_type: String = RARE_LOOT.pick_random()
		result[rare_type] = randi_range(RARE_AMOUNT_RANGE.x, RARE_AMOUNT_RANGE.y)
	return result

## Spawns GUARD_COUNT enemies in a small ring around this village, parented
## under the same chunk this village itself lives under (matching
## SpawnManager.spawn_one_enemy's own "just needs to be in the tree and in
## the 'enemies' group" convention -- Enemy's own AI already finds and
## chases the nearest blob on its own, no village-side targeting needed).
## Picks kinds from the parent chunk's own biome list when available (same
## as SpawnManager.spawn_one_enemy), falling back to the full EnemyKinds
## roster if this village was ever placed with no chunk parent (e.g. a
## future debug-spawn path).
func _spawn_guards() -> void:
	var parent := get_parent()
	var kind_ids: Array = parent.biome.enemy_kind_ids if parent and "biome" in parent and parent.biome else EnemyKinds.get_ordered_ids()
	for i in GUARD_COUNT:
		var angle := (TAU / GUARD_COUNT) * i
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * GUARD_SPAWN_RADIUS
		var guard: Node3D = SpawnManager.ENEMY_SCENE.instantiate()
		guard.kind_id = kind_ids.pick_random()
		parent.add_child(guard)
		guard.global_position = global_position + offset
		_guards.append(guard)

## Whether every spawned guard is now dead/freed and this village hasn't
## already been looted this cycle.
func is_raidable() -> bool:
	if _looted:
		return false
	for guard in _guards:
		if is_instance_valid(guard):
			return false
	return true

## Called by SelectionManager when the player clicks this village. Steals
## the whole loot table if undefended (see is_raidable), otherwise just
## warns -- clicking never opens a modal panel the way Chest/FriendlyVillage
## do, since there's nothing to choose, only "can I loot this yet."
func try_raid() -> void:
	if not is_raidable():
		Effects.spawn_floating_text(get_parent(), global_position + Vector3(0.0, 2.0, 0.0), "Defeat the guards first!", WARNING_COLOR)
		return
	for resource_type in loot.keys():
		GameManager.add_resource(resource_type, loot[resource_type])
	Effects.spawn_floating_text(get_parent(), global_position + Vector3(0.0, 2.0, 0.0), "Village raided!", LOOT_COLOR)
	Effects.spawn_command_marker(get_parent(), global_position + Vector3(0.0, 0.05, 0.0), LOOT_COLOR)
	_looted = true
	_respawn_elapsed = 0.0

## Brings the village back up: resets the looted flag, rerolls loot, and
## spawns a fresh guard band (the old, now-dead ones are simply dropped from
## _guards -- already freed by combat, nothing left to clean up).
func _respawn() -> void:
	_looted = false
	_respawn_elapsed = 0.0
	loot = _roll_loot()
	_guards.clear()
	_spawn_guards()
