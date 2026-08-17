extends Node
## Cross-run persistent progression: a separate currency ("prestige points")
## earned once per run (see World's End Run button, which banks it and
## returns to MainMenu) and spent on small permanent bonuses that apply to
## every future run from the moment it starts -- unlike GameManager's own
## upgrade_levels, which reset with every new World scene since GameManager
## itself is just a regular autoload with no persistence of its own.
##
## Persisted to disk (ConfigFile under user://) since it's the one piece of
## state in this project meant to survive not just a scene change but the
## game actually closing -- see feature backlog: "Add a Main Menu ... --
## Upgrades spends meta-progression points earned from prior runs on
## permanent bonuses for future ones." Nothing in the backlog specified
## *how* points are earned or *what* they buy -- both designed here: points
## scale with how far a run got (day reached, houses built, see
## World._on_end_run_pressed), and each upgrade is a small permanent
## multiplier/bonus GameManager reads at run-start rather than a one-off
## consumable, so a purchase compounds across every future run instead of
## being spent once and forgotten.

signal changed

const SAVE_PATH := "user://meta_progression.cfg"

## Same linear-growth shape as GameManager.UPGRADE_COST_BASE/STEP, just a
## separate, steeper curve since prestige points are meant to be scarce
## (earned once per run, not harvested continuously).
const UPGRADE_COST_BASE := 3
const UPGRADE_COST_STEP := 2

const HARVEST_BONUS_PER_LEVEL := 0.05
const POPULATION_BONUS_PER_LEVEL := 2
const STARTING_WOOD_PER_LEVEL := 25

## Every purchasable meta-upgrade, in the order UpgradesPanel lists them.
const UPGRADE_IDS := ["harvest", "population", "starting_wood"]
const UPGRADE_DISPLAY_NAMES := {
	"harvest": "Harvest Yield",
	"population": "Population Cap",
	"starting_wood": "Starting Wood",
}

var prestige_points: int = 0
var upgrade_levels: Dictionary = {
	"harvest": 0,
	"population": 0,
	"starting_wood": 0,
}


## Godot lifecycle hook: loads whatever was saved from a previous session
## (a fresh install simply keeps the zeroed defaults above).
func _ready() -> void:
	_load()

## Awards `amount` prestige points (see World._on_end_run_pressed for how
## much a given run earns) and saves immediately, so points survive even if
## the game is closed before spending them.
func earn_prestige(amount: int) -> void:
	if amount <= 0:
		return
	prestige_points += amount
	_save()
	changed.emit()

## Current purchased level of `upgrade_id` (0 if never bought).
func get_upgrade_level(upgrade_id: String) -> int:
	return upgrade_levels.get(upgrade_id, 0)

## Prestige-point cost of the *next* level of `upgrade_id`.
func get_upgrade_cost(upgrade_id: String) -> int:
	return UPGRADE_COST_BASE + get_upgrade_level(upgrade_id) * UPGRADE_COST_STEP

func can_afford_upgrade(upgrade_id: String) -> bool:
	return prestige_points >= get_upgrade_cost(upgrade_id)

## Attempts to buy the next level of `upgrade_id`: spends the points and
## bumps the level (saving immediately) if affordable, otherwise leaves
## everything untouched. Returns whether the purchase went through.
func try_purchase_upgrade(upgrade_id: String) -> bool:
	if not can_afford_upgrade(upgrade_id):
		return false
	prestige_points -= get_upgrade_cost(upgrade_id)
	upgrade_levels[upgrade_id] = get_upgrade_level(upgrade_id) + 1
	_save()
	changed.emit()
	return true

## Multiplier GameManager.get_strength_multiplier should stack on top of its
## own in-run "strength" upgrade -- a permanent, run-independent bonus to
## harvest yield.
func harvest_bonus_multiplier() -> float:
	return 1.0 + get_upgrade_level("harvest") * HARVEST_BONUS_PER_LEVEL

## Flat bonus GameManager.get_population_cap should add to its own
## BASE_POPULATION_CAP -- lets a new run support a couple more blobs before
## the first House even goes up.
func population_bonus() -> int:
	return get_upgrade_level("population") * POPULATION_BONUS_PER_LEVEL

## Flat wood GameManager should start a fresh run's stockpile with, on top
## of its own hardcoded starting amount.
func starting_wood_bonus() -> int:
	return get_upgrade_level("starting_wood") * STARTING_WOOD_PER_LEVEL

## Wipes all meta-progression back to a fresh install's defaults -- exposed
## via OptionsPanel's General tab as a deliberate "start over" escape hatch,
## since there is otherwise no way back once points are spent.
func reset() -> void:
	prestige_points = 0
	for upgrade_id in UPGRADE_IDS:
		upgrade_levels[upgrade_id] = 0
	_save()
	changed.emit()

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "prestige_points", prestige_points)
	for upgrade_id in UPGRADE_IDS:
		config.set_value("upgrades", upgrade_id, get_upgrade_level(upgrade_id))
	config.save(SAVE_PATH)

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	prestige_points = config.get_value("meta", "prestige_points", 0)
	for upgrade_id in UPGRADE_IDS:
		upgrade_levels[upgrade_id] = config.get_value("upgrades", upgrade_id, 0)
