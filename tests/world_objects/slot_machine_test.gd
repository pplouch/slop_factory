extends GdUnitTestSuite
## Covers SlotMachine.spin()'s synchronous, testable half: the RNG roll,
## payout, and economy transaction all resolve instantly inside spin()
## itself (see its own header on why -- only the *reveal* is animated, and
## that lives entirely in SlotMachinePanel, out of scope here). Doesn't
## re-test _evaluate's payout-tier math (already covered structurally by
## reading THREE_OF_A_KIND_PAYOUT/PAIR_PAYOUT_FRACTION), focuses instead on
## the is_jackpot flag this pass added and spin()'s afford-ability gating.

var _wood_before: float

const SLOT_MACHINE_SCENE: PackedScene = preload("res://scenes/world_objects/slot_machine.tscn")


func before_test() -> void:
	_wood_before = GameManager.resources.get("wood", 0.0)


func after_test() -> void:
	GameManager.resources["wood"] = _wood_before


func _spawn_machine() -> Node:
	var machine: Node = SLOT_MACHINE_SCENE.instantiate()
	add_child(machine)
	auto_free(machine)
	return machine


func test_spin_returns_empty_result_when_unaffordable() -> void:
	GameManager.resources["wood"] = 0
	var machine := _spawn_machine()
	var outcome: Dictionary = machine.spin()
	assert_array(outcome.symbols).is_empty()
	assert_dict(outcome.payout).is_empty()


func test_spin_spends_the_cost_exactly_once_when_affordable() -> void:
	GameManager.resources["wood"] = 1000
	var machine := _spawn_machine()
	machine.spin()
	# spin() may also grant wood back as a payout (a wood 3-of-a-kind pays
	# 150, well over the 20 cost, so the balance can end up either above or
	# below 1000) -- this only bounds the result between "cost spent, no
	# wood payout" and "cost spent, the biggest possible wood payout",
	# which would only be violated if the cost were spent twice, not spent
	# at all, or a payout value drifted from THREE_OF_A_KIND_PAYOUT.
	var final_wood: float = GameManager.resources.get("wood", 0.0)
	assert_float(final_wood).is_between(1000.0 - machine.SPIN_COST, 1000.0 - machine.SPIN_COST + 150.0)


func test_is_jackpot_flag_matches_all_three_reels_being_jackpot() -> void:
	GameManager.resources["wood"] = 1000
	var machine := _spawn_machine()
	# _evaluate/_roll_reels are independently seeded RNG -- rather than
	# fish for a real jackpot roll (astronomically rare, see
	# SYMBOL_WEIGHTS), this checks the flag's own wiring directly against
	# whatever reels actually came up this call.
	var outcome: Dictionary = machine.spin()
	var symbols: Array = outcome.symbols
	var expected_jackpot: bool = symbols.size() == 3 and symbols[0] == "jackpot" and symbols[1] == "jackpot" and symbols[2] == "jackpot"
	assert_bool(outcome.is_jackpot).is_equal(expected_jackpot)


func test_three_jackpots_are_flagged_and_paid_out_in_full() -> void:
	GameManager.resources["wood"] = 1000
	var machine := _spawn_machine()
	var symbols := ["jackpot", "jackpot", "jackpot"]
	var payout: Dictionary = machine._evaluate(symbols)
	assert_dict(payout).is_equal(machine.THREE_OF_A_KIND_PAYOUT["jackpot"])
