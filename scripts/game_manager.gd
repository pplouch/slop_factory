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

var resources: Dictionary = {
	"wood": 0,
	"stone": 0,
}

var upgrade_levels: Dictionary = {
	"speed": 0,
	"strength": 0,
	"efficiency": 0,
	"capacity": 0,
	"growth": 0,
}


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
