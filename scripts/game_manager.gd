extends Node
## Global game state: the player's resource stockpile and building-upgrade
## levels.
##
## Registered as an autoload (Singleton pattern) so any script can reach it
## as `GameManager` without a node-path reference. State changes are
## broadcast via signals (Observer pattern) -- HUD, BuildingMenu, and Blob
## all react to `resource_changed`/`upgrade_changed` instead of polling this
## script every frame.

## Fired whenever a resource total changes (harvested in, spent on an
## upgrade or a hire). HUD and BuildingMenu listen to keep their labels in sync.
signal resource_changed(resource_type: String, total: int)
## Fired whenever an upgrade is purchased. Blob listens so units already in
## the field pick up the new stat immediately, not just future spawns;
## Building listens so its spawn timer reacts to the "growth" stat.
signal upgrade_changed(stat: String, level: int)
## Fired whenever a building type is unlocked. BuildPalette listens to reveal
## its button; BuildingMenu listens to drop it from the "Unlock Buildings" list.
signal building_unlocked(building_id: String)
## Fired whenever the colony's starving/dehydrated status actually changes
## (not every consumption tick -- only on a flip). Blob listens to
## immediately apply/lift the starvation penalty on units already in the
## field, the same way it reacts to upgrade_changed.
signal colony_supply_changed

## Every upgradeable stat, in the order BuildingMenu displays them. Adding a
## new upgrade is: add it here, add its display name and per-level bonus
## below, and add a multiplier/bonus getter -- no UI changes required, since
## BuildingMenu builds its rows by iterating this array.
const UPGRADE_STATS := ["speed", "strength", "efficiency", "capacity", "growth"]
const UPGRADE_DISPLAY_NAMES := {
	"speed": "Speed",
	"strength": "Strength",
	"efficiency": "Efficiency",
	"capacity": "Capacity",
	"growth": "Growth",
}

const UPGRADE_COST_BASE := 10
const UPGRADE_COST_STEP := 10

const SPEED_BONUS_PER_LEVEL := 0.15
const STRENGTH_BONUS_PER_LEVEL := 0.25
const EFFICIENCY_BONUS_PER_LEVEL := 0.12
const CAPACITY_BONUS_PER_LEVEL := 3
const GROWTH_BONUS_PER_LEVEL := 0.1

## Enemies start noticeably weaker and ramp up to full strength over the
## first few minutes, rather than hitting the player at full difficulty
## from the very first spawn. Only affects stats baked in at spawn time
## (see Enemy._ready), so the ramp shows up as later enemies being tougher
## than earlier ones, not existing enemies changing mid-fight.
const DIFFICULTY_RAMP_SECONDS := 240.0
const DIFFICULTY_START_MULTIPLIER := 0.35

var _start_time_ms: int = 0

## Starts pre-stocked for debug convenience (so upgrades/hires/build mode
## can be exercised immediately without a harvesting grind).
var resources: Dictionary = {
	"wood": 100,
	"stone": 100,
	"planks": 100,
}

var upgrade_levels: Dictionary = {
	"speed": 0,
	"strength": 0,
	"efficiency": 0,
	"capacity": 0,
	"growth": 0,
}

## Tech-tree unlock state, keyed by BuildingKinds id. Town Hall is the root
## of the tree (always unlocked, since the player needs to build *something*
## to receive resources at all) -- everything else starts locked and must be
## bought via try_unlock_building before BuildPalette will show it.
var unlocked_buildings: Dictionary = {
	"town_hall": true,
}

# -- Colony food/water (see consume_colony_supplies) --
# Deliberately a colony-wide upkeep rather than per-blob hunger/thirst
# meters: every tick, the whole crew's food/water need is drained from the
# shared stockpile at once. Much simpler to reason about and to display
# (two more resource types in the same stockpile HUD already shows) while
# still making "keep food and water flowing in" a real ongoing concern.
const COLONY_FOOD_PER_BLOB := 1
const COLONY_WATER_PER_BLOB := 1
const STARVATION_SPEED_MULTIPLIER := 0.6
const STARVATION_HARVEST_MULTIPLIER := 0.6

var _colony_starving := false
var _colony_dehydrated := false


## Godot lifecycle hook: marks the moment the difficulty ramp starts
## counting from.
func _ready() -> void:
	_start_time_ms = Time.get_ticks_msec()

## Multiplier Enemy should apply to its threat stats (health, attack power)
## at spawn time, ramping linearly from DIFFICULTY_START_MULTIPLIER up to
## 1.0 over the first DIFFICULTY_RAMP_SECONDS of play, then holding steady.
func get_enemy_difficulty_multiplier() -> float:
	var elapsed_sec: float = (Time.get_ticks_msec() - _start_time_ms) / 1000.0
	var t: float = clamp(elapsed_sec / DIFFICULTY_RAMP_SECONDS, 0.0, 1.0)
	return lerp(DIFFICULTY_START_MULTIPLIER, 1.0, t)

## Adds `amount` of `resource_type` to the stockpile (negative amounts spend
## it; see try_purchase_upgrade) and notifies listeners. A no-op for a zero
## amount so depositing nothing doesn't spam the signal.
func add_resource(resource_type: String, amount: int) -> void:
	if amount == 0:
		return
	resources[resource_type] = resources.get(resource_type, 0) + amount
	resource_changed.emit(resource_type, resources[resource_type])

## Current stockpile total for `resource_type` (0 if never collected).
func get_resource(resource_type: String) -> int:
	return resources.get(resource_type, 0)

## Current purchased level of `stat` (0 if never upgraded).
func get_upgrade_level(stat: String) -> int:
	return upgrade_levels.get(stat, 0)

## Wood cost of the *next* level of `stat`. Linear growth
## (base + level * step) keeps early upgrades cheap and predictable.
func get_upgrade_cost(stat: String) -> int:
	return UPGRADE_COST_BASE + get_upgrade_level(stat) * UPGRADE_COST_STEP

## Whether the player currently has enough wood to buy the next level of
## `stat`. Used to grey out BuildingMenu's upgrade buttons.
func can_afford_upgrade(stat: String) -> bool:
	return get_resource("wood") >= get_upgrade_cost(stat)

## Whether the player currently has enough wood to hire a blob costing
## `cost` wood. Used to grey out BuildingMenu's hire buttons.
func can_afford_cost(cost: int) -> bool:
	return get_resource("wood") >= cost

## Attempts to buy the next level of `stat`: spends the wood and bumps the
## level (emitting both signals) if affordable, otherwise leaves everything
## untouched. Returns whether the purchase went through.
func try_purchase_upgrade(stat: String) -> bool:
	if not can_afford_upgrade(stat):
		return false
	var cost := get_upgrade_cost(stat)
	resources["wood"] -= cost
	resource_changed.emit("wood", resources["wood"])
	upgrade_levels[stat] = get_upgrade_level(stat) + 1
	upgrade_changed.emit(stat, upgrade_levels[stat])
	return true

## Attempts to spend `cost` wood on something that isn't a stat upgrade
## (currently: hiring a blob). Returns whether the spend went through.
func try_spend_wood(cost: int) -> bool:
	if not can_afford_cost(cost):
		return false
	resources["wood"] -= cost
	resource_changed.emit("wood", resources["wood"])
	return true

## Multiplier blobs should apply to their base movement speed, given the
## current "speed" upgrade level.
func get_speed_multiplier() -> float:
	return 1.0 + get_upgrade_level("speed") * SPEED_BONUS_PER_LEVEL

## Multiplier blobs should apply to their base harvest yield (amount per
## tick), given the current "strength" upgrade level.
func get_strength_multiplier() -> float:
	return 1.0 + get_upgrade_level("strength") * STRENGTH_BONUS_PER_LEVEL

## Multiplier blobs should apply to their harvest tick *rate* (higher means
## shorter time between ticks), given the current "efficiency" upgrade level.
func get_efficiency_multiplier() -> float:
	return 1.0 + get_upgrade_level("efficiency") * EFFICIENCY_BONUS_PER_LEVEL

## Flat bonus blobs should add to their base carry capacity, given the
## current "capacity" upgrade level.
func get_capacity_bonus() -> int:
	return get_upgrade_level("capacity") * CAPACITY_BONUS_PER_LEVEL

## Multiplier the building should apply to its automatic spawn rate (higher
## means new blobs arrive more often), given the current "growth" upgrade level.
func get_growth_multiplier() -> float:
	return 1.0 + get_upgrade_level("growth") * GROWTH_BONUS_PER_LEVEL

## Whether `building_id` has been unlocked and can be placed in Build Mode.
func is_building_unlocked(building_id: String) -> bool:
	return unlocked_buildings.get(building_id, false)

## Whether `building_id` can be unlocked right now: it exists, isn't already
## unlocked, its prerequisite (if any) is already unlocked, and the player
## can afford its wood cost. Used to grey out BuildingMenu's unlock buttons.
func can_unlock_building(building_id: String) -> bool:
	var kind = BuildingKinds.get_kind(building_id)
	if kind == null or is_building_unlocked(building_id):
		return false
	if kind.requires != "" and not is_building_unlocked(kind.requires):
		return false
	return get_resource("wood") >= kind.unlock_cost

## Attempts to unlock `building_id`: spends the wood and marks it unlocked
## (emitting building_unlocked) if eligible, otherwise leaves state
## untouched. Returns whether the unlock went through.
func try_unlock_building(building_id: String) -> bool:
	if not can_unlock_building(building_id):
		return false
	var kind = BuildingKinds.get_kind(building_id)
	resources["wood"] -= kind.unlock_cost
	resource_changed.emit("wood", resources["wood"])
	unlocked_buildings[building_id] = true
	building_unlocked.emit(building_id)
	return true

## Drains `blob_count` worth of food/water upkeep from the stockpile (see
## the "colony food/water" section above). Called periodically by World,
## which owns the timer and the actual blob count -- GameManager itself
## never queries the scene tree. Whichever of food/water can't be fully
## paid leaves the colony starving/dehydrated (no partial-payment
## shortfall carried over -- next tick starts fresh) until enough is
## stockpiled again; colony_supply_changed only fires on an actual flip,
## not every tick, so listeners don't refresh needlessly.
func consume_colony_supplies(blob_count: int) -> void:
	if blob_count <= 0:
		return
	var still_starving: bool = get_resource("food") < blob_count * COLONY_FOOD_PER_BLOB
	var still_dehydrated: bool = get_resource("water") < blob_count * COLONY_WATER_PER_BLOB
	if not still_starving:
		add_resource("food", -blob_count * COLONY_FOOD_PER_BLOB)
	if not still_dehydrated:
		add_resource("water", -blob_count * COLONY_WATER_PER_BLOB)

	if still_starving != _colony_starving or still_dehydrated != _colony_dehydrated:
		_colony_starving = still_starving
		_colony_dehydrated = still_dehydrated
		colony_supply_changed.emit()

## Whether the colony currently lacks enough food or water to feed
## everyone -- used by BuildingMenu-style UI and by Blob's stat refresh.
func is_colony_starving() -> bool:
	return _colony_starving or _colony_dehydrated

## Multiplier blobs should apply to speed while the colony is starving/
## dehydrated (1.0 the rest of the time).
func get_starvation_speed_multiplier() -> float:
	return STARVATION_SPEED_MULTIPLIER if is_colony_starving() else 1.0

## Multiplier blobs should apply to harvest yield while the colony is
## starving/dehydrated (1.0 the rest of the time).
func get_starvation_harvest_multiplier() -> float:
	return STARVATION_HARVEST_MULTIPLIER if is_colony_starving() else 1.0
