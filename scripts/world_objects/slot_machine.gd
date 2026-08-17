class_name SlotMachine
extends StaticBody3D
## A "wanky dandy" gambling mini-game scattered across the map (see
## Chunk._maybe_spawn_slot_machine). The backlog's own "mini-games" item was
## deliberately left open-ended with no fixed spec -- a classic 3-reel slot
## machine felt like the most legible "fun distraction" to bolt onto an
## otherwise serious factory/survival loop, and it reuses the exact same
## "Chunk-scattered clickable world object + its own UI panel" shape
## Chest/FriendlyVillage/EnemyVillage already established rather than
## inventing a new placement/interaction pattern from scratch.

const SPIN_COST := 20

## Symbol -> its 3-of-a-kind payout. Spawn odds (SYMBOL_WEIGHTS, parallel
## array) are weighted toward the everyday "wood" symbol, with "jackpot"
## both rarest and by far the best payout -- the classic slot-machine shape
## of mostly small-or-no wins with one rare big one.
const SYMBOLS := ["wood", "stone", "knowledge", "gold", "jackpot"]
const SYMBOL_WEIGHTS := [40, 30, 15, 10, 5]
const THREE_OF_A_KIND_PAYOUT := {
	"wood": {"wood": 150},
	"stone": {"stone": 150},
	"knowledge": {"knowledge": 100},
	"gold": {"gold": 60},
	"jackpot": {"gold": 100, "knowledge": 200},
}
## A mere pair pays out this fraction of its symbol's full 3-of-a-kind
## payout (rounded) -- the big reward above is reserved for landing all
## three reels the same, including for a jackpot pair.
const PAIR_PAYOUT_FRACTION := 0.25


## Godot lifecycle hook: makes this machine discoverable/clickable (see
## SelectionManager.handle_click_select).
func _ready() -> void:
	add_to_group("slot_machines")

## Whether the player can currently afford a spin.
func can_afford_spin() -> bool:
	return GameManager.can_afford("wood", SPIN_COST)

## Spends SPIN_COST wood, rolls 3 reels, and grants whatever they pay out
## (see _evaluate) -- returns a no-op empty result (no symbols, no payout)
## if the spin couldn't even be paid for, so SlotMachinePanel can tell "you
## can't afford this" apart from "you spun and lost."
func spin() -> Dictionary:
	if not GameManager.try_spend("wood", SPIN_COST):
		return {"symbols": [], "payout": {}}
	var symbols := _roll_reels()
	var payout := _evaluate(symbols)
	for resource_type in payout.keys():
		GameManager.add_resource(resource_type, payout[resource_type])
	if not payout.is_empty():
		Effects.spawn_command_marker(get_parent(), global_position + Vector3(0.0, 0.05, 0.0), Color(1.0, 0.85, 0.3, 1.0))
	return {"symbols": symbols, "payout": payout}

## Rolls one weighted-random symbol per reel (see SYMBOLS/SYMBOL_WEIGHTS).
func _roll_reels() -> Array:
	var total_weight := 0
	for w in SYMBOL_WEIGHTS:
		total_weight += w
	var reels: Array = []
	for i in 3:
		var roll := randi_range(1, total_weight)
		var cumulative := 0
		for j in SYMBOLS.size():
			cumulative += SYMBOL_WEIGHTS[j]
			if roll <= cumulative:
				reels.append(SYMBOLS[j])
				break
	return reels

## Pure function (no RNG, no side effects) so a debug hook can verify every
## payout tier by feeding it fixed reel outcomes directly: 3-of-a-kind pays
## THREE_OF_A_KIND_PAYOUT in full, exactly 2 matching pays PAIR_PAYOUT_FRACTION
## of it, and no match at all pays nothing.
func _evaluate(symbols: Array) -> Dictionary:
	if symbols.size() != 3:
		return {}
	if symbols[0] == symbols[1] and symbols[1] == symbols[2]:
		return THREE_OF_A_KIND_PAYOUT[symbols[0]].duplicate()

	var matched_symbol := ""
	if symbols[0] == symbols[1] or symbols[0] == symbols[2]:
		matched_symbol = symbols[0]
	elif symbols[1] == symbols[2]:
		matched_symbol = symbols[1]
	if matched_symbol == "":
		return {}

	var result: Dictionary = {}
	for resource_type in THREE_OF_A_KIND_PAYOUT[matched_symbol].keys():
		result[resource_type] = int(round(THREE_OF_A_KIND_PAYOUT[matched_symbol][resource_type] * PAIR_PAYOUT_FRACTION))
	return result
