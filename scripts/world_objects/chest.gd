class_name Chest
extends StaticBody3D
## A one-time lootable world object scattered across the map (see
## Chunk._maybe_spawn_chest) -- unlike ResourceNode (finite but repeatedly
## harvestable, then regrows over time), a Chest holds a single random
## haul of resources, grants it all at once when opened, and is removed
## for good. Clicking one opens ChestPanel (see scripts/ui/chest_panel.gd)
## instead of being blob-targetable like a resource node -- looting a
## chest is a direct player action, not ambient gathering labor.

## Resource type -> amount, generated once in _ready() if left empty (the
## normal case; a pre-set dictionary is only used by tests). Handed to
## GameManager in full the moment the player opens this chest.
var loot: Dictionary = {}

## Candidate resource types a chest can contain, weighted toward the
## everyday ones (wood/stone/planks) with rarer ore types (plus a
## knowledge windfall) mixed in as a smaller, exciting bonus rather than
## the norm.
const COMMON_LOOT := ["wood", "stone", "planks"]
const RARE_LOOT := ["iron", "gold", "silver", "platinum", "slopium", "knowledge"]
const RARE_CHANCE := 0.35
const COMMON_AMOUNT_RANGE := Vector2i(20, 60)
const RARE_AMOUNT_RANGE := Vector2i(5, 20)

## How far the lid tilts open (radians) and how long the whole reveal
## flourish plays before the chest is actually freed (see open()) -- purely
## cosmetic timing, resources are already granted by the time this starts.
const LID_OPEN_ANGLE := -1.2
const LID_TWEEN_DURATION := 0.3
const GLOW_FADE_DURATION := 0.35

@onready var _lid: MeshInstance3D = $Lid
@onready var _glow: OmniLight3D = $GoldGlint


## Godot lifecycle hook: makes this chest discoverable/clickable (see
## SelectionManager.handle_click_select) and rolls its loot if none was
## pre-set.
func _ready() -> void:
	add_to_group("chests")
	if loot.is_empty():
		loot = _roll_loot()

## Rolls a random haul: 1-2 common resource types, plus a RARE_CHANCE
## chance of one additional rare bonus type -- most chests are a modest,
## reliable trickle of everyday resources, with an occasional bigger prize.
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

## Grants this chest's whole loot table to the stockpile immediately (the
## economy never waits on an animation), then plays a lid-opening flourish
## (a tween swinging the lid back, a bigger gold particle burst, and a
## glow-light pulse) before actually removing the chest -- called by
## ChestPanel's Open button. Unlike the old instant queue_free, this reads
## as a real "treasure chest" moment (see feature request: "improve Chest
## UI... filled with VFX and animation, like a real slot machine").
## Deliberately left un-awaited by every caller: ChestPanel fires this and
## moves on, letting the flourish play out in the background.
func open() -> void:
	for resource_type in loot.keys():
		GameManager.add_resource(resource_type, loot[resource_type])
	remove_from_group("chests")
	collision_layer = 0
	Effects.spawn_impact(get_parent(), global_position + Vector3(0.0, 0.4, 0.0), Color(1.0, 0.85, 0.3, 1.0), 20)
	Effects.spawn_command_marker(get_parent(), global_position + Vector3(0.0, 0.05, 0.0), Color(1.0, 0.85, 0.3, 1.0))

	var open_tween := create_tween()
	open_tween.set_parallel(true)
	open_tween.tween_property(_lid, "rotation:x", LID_OPEN_ANGLE, LID_TWEEN_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	open_tween.tween_property(_lid, "position:y", _lid.position.y + 0.1, LID_TWEEN_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	open_tween.tween_property(_glow, "light_energy", 3.0, LID_TWEEN_DURATION * 0.5)
	await get_tree().create_timer(LID_TWEEN_DURATION).timeout

	var fade_tween := create_tween()
	fade_tween.tween_property(_glow, "light_energy", 0.0, GLOW_FADE_DURATION)
	await fade_tween.finished
	queue_free()
