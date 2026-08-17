class_name FriendlyVillage
extends StaticBody3D
## A friendly trading outpost scattered across the map (see
## Chunk._maybe_spawn_village) offering a small, fixed set of resource-for-
## resource trades, repeatable as often as the player can afford them --
## unlike Chest's one-time haul, a village never depletes or disappears.
## Clicking one opens VillagePanel (scripts/ui/village_panel.gd).

## Every possible trade the game can roll from -- deliberately a single
## give/receive resource pair each rather than a multi-resource cost dict,
## since GameManager's can_afford/try_spend/add_resource are already
## single-resource operations and a village trade is meant to read as one
## simple swap, not a shopping cart.
const TRADE_POOL := [
	{"give": "wood", "give_amount": 40, "receive": "stone", "receive_amount": 25},
	{"give": "stone", "give_amount": 40, "receive": "wood", "receive_amount": 25},
	{"give": "wood", "give_amount": 30, "receive": "knowledge", "receive_amount": 10},
	{"give": "planks", "give_amount": 20, "receive": "knowledge", "receive_amount": 15},
	{"give": "stone", "give_amount": 50, "receive": "iron", "receive_amount": 10},
	{"give": "knowledge", "give_amount": 20, "receive": "gold", "receive_amount": 8},
]
const OFFER_COUNT := 3

## This village's own rolled subset of TRADE_POOL, picked once at spawn and
## kept fixed for its whole lifetime -- a player who finds a good trade can
## rely on it still being there on a later visit, rather than it re-rolling
## out from under them.
var offers: Array = []


## Godot lifecycle hook: makes this village discoverable/clickable (see
## SelectionManager.handle_click_select) and rolls its fixed offer list if
## none was pre-set (a pre-set list is only used by tests).
func _ready() -> void:
	add_to_group("friendly_villages")
	if offers.is_empty():
		var pool := TRADE_POOL.duplicate(true)
		pool.shuffle()
		offers = pool.slice(0, min(OFFER_COUNT, pool.size()))

## Whether the player can currently afford trade `index`'s give side.
func can_afford_offer(index: int) -> bool:
	var offer: Dictionary = offers[index]
	return GameManager.can_afford(offer.give, offer.give_amount)

## Attempts trade `index`: spends the give side and grants the receive side
## if affordable, leaving everything untouched otherwise. Returns whether
## the trade went through, so VillagePanel knows whether anything happened.
func try_trade(index: int) -> bool:
	var offer: Dictionary = offers[index]
	if not GameManager.try_spend(offer.give, offer.give_amount):
		return false
	GameManager.add_resource(offer.receive, offer.receive_amount)
	Effects.spawn_command_marker(get_parent(), global_position + Vector3(0.0, 0.05, 0.0), Effects.resource_color(offer.receive))
	return true
