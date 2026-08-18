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
## Fired whenever a blob archetype is unlocked. BuildingMenu listens to
## reveal its Hire row; TechTreePanel listens to drop it from its own list.
signal blob_kind_unlocked(blob_kind_id: String)

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
## can be exercised immediately without a harvesting grind). The wood
## figure gets MetaProgression's starting_wood_bonus added in _ready() --
## kept as a plain literal here rather than computed inline so a script
## reading this dict's shape at parse time (e.g. a debug hook) still sees a
## plain baseline number.
var resources: Dictionary = {
	"wood": 100,
	"stone": 100,
	"planks": 100,
	"knowledge": 100,
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
## to receive resources at all); Wall, Belt, and Road (LinkableBuilding
## entries, see scripts/core/linkable_building.gd) are seeded unlocked too --
## Wall/Belt since they were always-available factory pieces before joining
## the tech tree, Road since it's basic infrastructure with no real reason
## to gate behind research (unlike Pipe, which needs Water Tank first). A
## new player also has no Town Hall yet to unlock anything else from.
## Everything else starts locked and must be bought via try_unlock_building
## before BuildPalette will show it.
var unlocked_buildings: Dictionary = {
	"town_hall": true,
	"wall": true,
	"gate": true,
	"belt": true,
	"road": true,
}

## Tech-tree unlock state for blob archetypes, keyed by BlobKinds id -- the
## same "spend knowledge once, permanently available" shape as
## unlocked_buildings, just for hireable kinds instead of buildings. Only
## "worker" (BlobKinds' own _default_id) is seeded unlocked; the rest
## (scout/hauler/brute/builder) must be bought via try_unlock_blob_kind
## before BuildingMenu's Hire section will show a row for them.
var unlocked_blob_kinds: Dictionary = {
	"worker": true,
}

## Baseline population cap before any House is built -- comfortably above
## SpawnManager.FOUNDER_BLOB_COUNT (3) so a new game can hire a couple of
## blobs before needing to build a House at all.
const BASE_POPULATION_CAP := 5
## Extra population cap granted per *finished* House (see get_population_cap
## -- a House still under construction doesn't count, same as every other
## building's "non-functional until built" convention).
const POPULATION_PER_HOUSE := 5

## Godot lifecycle hook: marks the moment the difficulty ramp starts
## counting from, and grants this run's starting-wood bonus from
## MetaProgression (see feature backlog: main menu + meta-progression) --
## applied once here rather than baked into the `resources` dict literal
## above, so a purchased upgrade level takes effect on every future run
## without needing to touch this file again.
func _ready() -> void:
	_start_time_ms = Time.get_ticks_msec()
	resources["wood"] += MetaProgression.starting_wood_bonus()

## Current number of blobs alive -- computed on demand from the "blobs"
## group rather than tracked as a separate counter, so it can never drift
## out of sync with reality regardless of how a blob comes to exist or die
## (hired, freely spawned, debug-spawned, killed in combat, ...).
func get_current_population() -> int:
	return get_tree().get_nodes_in_group("blobs").size()

## Current population cap: a base allowance (plus MetaProgression's own
## permanent population bonus, see feature backlog: main menu +
## meta-progression) plus POPULATION_PER_HOUSE for every finished House
## (see feature backlog: "Have a maximum population stat. Building houses
## will increase this stat.").
func get_population_cap() -> int:
	var house_count := get_house_count()
	return BASE_POPULATION_CAP + MetaProgression.population_bonus() + house_count * POPULATION_PER_HOUSE

## Number of finished (not under-construction) Houses currently standing --
## split out of get_population_cap so World's End Run flow (see feature
## backlog: main menu + meta-progression) can factor "how many Houses did
## this run build" into the prestige points it banks without duplicating
## this same scan.
func get_house_count() -> int:
	var house_count := 0
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building) or building.get("kind_id") != "house":
			continue
		if "is_under_construction" in building and building.is_under_construction:
			continue
		house_count += 1
	return house_count

## Whether one more blob could be hired/spawned right now without exceeding
## the population cap. Checked by both Building.hire_blob (paid) and its
## free auto-spawn timer -- a cap that only blocked paid hires would be
## trivially bypassed by passive growth.
func can_hire_more() -> bool:
	return get_current_population() < get_population_cap()

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

## Whether the player currently has enough of `resource_type` to spend `cost`
## on it. Generic counterpart to can_afford_cost (which always assumes
## wood) -- used by the tech tree and per-building upgrades, both of which
## spend "knowledge" (see ResearchCenter/BuildableStructure.try_upgrade)
## rather than wood.
func can_afford(resource_type: String, cost: int) -> bool:
	return get_resource(resource_type) >= cost

## Attempts to spend `cost` of `resource_type`. Generic counterpart to
## try_spend_wood.
func try_spend(resource_type: String, cost: int) -> bool:
	if not can_afford(resource_type, cost):
		return false
	resources[resource_type] = resources.get(resource_type, 0) - cost
	resource_changed.emit(resource_type, resources[resource_type])
	return true

## Multiplier blobs should apply to their base movement speed, given the
## current "speed" upgrade level.
func get_speed_multiplier() -> float:
	return 1.0 + get_upgrade_level("speed") * SPEED_BONUS_PER_LEVEL

## Multiplier blobs should apply to their base harvest yield (amount per
## tick), given the current "strength" upgrade level and MetaProgression's
## own permanent harvest bonus (see feature backlog: main menu +
## meta-progression) -- the two stack multiplicatively, so a
## meta-upgrade's benefit compounds with in-run upgrades rather than being
## overridden by them.
func get_strength_multiplier() -> float:
	return (1.0 + get_upgrade_level("strength") * STRENGTH_BONUS_PER_LEVEL) * MetaProgression.harvest_bonus_multiplier()

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
## can afford its knowledge cost. Used to grey out TechTreePanel's unlock
## buttons. Knowledge (not wood) is what the tech tree spends -- see
## ResearchCenter, its source -- so building tiers have their own economy
## distinct from the wood spent placing/upgrading an individual instance.
func can_unlock_building(building_id: String) -> bool:
	var kind = BuildingKinds.get_kind(building_id)
	if kind == null or is_building_unlocked(building_id):
		return false
	if kind.requires != "" and not is_building_unlocked(kind.requires):
		return false
	return can_afford("knowledge", kind.unlock_cost)

## Attempts to unlock `building_id`: spends the knowledge and marks it
## unlocked (emitting building_unlocked) if eligible, otherwise leaves state
## untouched. Returns whether the unlock went through.
func try_unlock_building(building_id: String) -> bool:
	if not can_unlock_building(building_id):
		return false
	var kind = BuildingKinds.get_kind(building_id)
	try_spend("knowledge", kind.unlock_cost)
	unlocked_buildings[building_id] = true
	building_unlocked.emit(building_id)
	return true

## Whether `blob_kind_id` has been unlocked and can be hired.
func is_blob_kind_unlocked(blob_kind_id: String) -> bool:
	return unlocked_blob_kinds.get(blob_kind_id, false)

## Whether `blob_kind_id` can be unlocked right now: isn't already unlocked,
## its prerequisite kind (if any) is already unlocked, and the player can
## afford its knowledge cost. Used to grey out TechTreePanel's blob-kind
## unlock buttons. Unlike can_unlock_building, doesn't need a "does this id
## even exist" null check -- BlobKinds falls back to "worker" for any
## unknown id (see BlobKinds._default_id) rather than returning null, and
## this is only ever called with ids from BlobKinds.get_ordered_ids().
func can_unlock_blob_kind(blob_kind_id: String) -> bool:
	if is_blob_kind_unlocked(blob_kind_id):
		return false
	var kind = BlobKinds.get_kind(blob_kind_id)
	if kind.requires != "" and not is_blob_kind_unlocked(kind.requires):
		return false
	return can_afford("knowledge", kind.unlock_cost)

## Attempts to unlock `blob_kind_id`: spends the knowledge and marks it
## unlocked (emitting blob_kind_unlocked) if eligible, otherwise leaves
## state untouched. Returns whether the unlock went through.
func try_unlock_blob_kind(blob_kind_id: String) -> bool:
	if not can_unlock_blob_kind(blob_kind_id):
		return false
	var kind = BlobKinds.get_kind(blob_kind_id)
	try_spend("knowledge", kind.unlock_cost)
	unlocked_blob_kinds[blob_kind_id] = true
	blob_kind_unlocked.emit(blob_kind_id)
	return true

