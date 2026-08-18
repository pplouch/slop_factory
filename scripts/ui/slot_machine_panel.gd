extends CanvasLayer
## Popup shown when the player clicks a SlotMachine (see the backlog's
## "wanky dandy" mini-game item, and SlotMachine's own header for why this
## specific shape was chosen) -- shows the 3 reels spinning down to a stop
## one at a time before revealing whatever they paid out (see
## SlotMachine.spin), and can be spun again as many times as the player can
## afford, unlike Chest's one-shot grant.
##
## The RNG/economy resolve synchronously inside SlotMachine.spin() the
## instant Spin is pressed (no exploit window from delaying that) -- only
## the *reveal* is staggered here (see feature request: "Slot machine UI...
## filled with VFX and animation, like a real slot machine"), cycling each
## reel through random symbol names and stopping them one at a time on the
## already-fixed result.

@onready var reel_labels: Array = [$Panel/VBox/ReelRow/Reel1, $Panel/VBox/ReelRow/Reel2, $Panel/VBox/ReelRow/Reel3]
@onready var result_label: Label = $Panel/VBox/ResultLabel
@onready var spin_button: Button = $Panel/VBox/SpinButton
@onready var close_button: Button = $CloseButton
@onready var backdrop: ColorRect = $Backdrop

## How often a still-spinning reel swaps to a new random symbol name, and
## when (in seconds since Spin was pressed) each of the 3 reels locks onto
## its real result -- staggered so they stop left-to-right like a real
## machine instead of all landing at once.
const SPIN_CYCLE_INTERVAL := 0.06
const REEL_STOP_TIMES := [0.5, 0.85, 1.25]
const REEL_LAND_BOUNCE_DURATION := 0.18
const RESULT_POP_DURATION := 0.3

var _tracked_machine: Node = null
## True from the moment Spin is pressed until the last reel has landed and
## the result is shown -- blocks a second spin and keeps _process's
## afford-ability refresh from fighting the button's own "spinning" state.
var _spinning := false


## Godot lifecycle hook: starts hidden.
func _ready() -> void:
	visible = false
	close_button.pressed.connect(close_panel)
	backdrop.gui_input.connect(_on_backdrop_gui_input)
	spin_button.pressed.connect(_on_spin_pressed)

func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()

## Opens the panel for `machine` with its reels showing unrevealed.
func open_for(machine: Node) -> void:
	_tracked_machine = machine
	visible = true
	for label in reel_labels:
		label.text = "?"
		label.scale = Vector2(1.0, 1.0)
	result_label.text = ""
	_refresh()

func close_panel() -> void:
	visible = false
	_tracked_machine = null

## Button handler for Spin: asks the tracked machine to actually spin (see
## SlotMachine.spin, which spends/grants resources and returns the final,
## already-decided result synchronously), then plays the staggered reel
## reveal before showing the win/lose message -- a no-op if the spin failed
## outright (unaffordable, or the machine vanished out from under this
## panel) or a spin is already mid-reveal.
func _on_spin_pressed() -> void:
	if _spinning or not is_instance_valid(_tracked_machine):
		return
	var outcome: Dictionary = _tracked_machine.spin()
	if outcome.symbols.is_empty():
		return
	_spinning = true
	spin_button.disabled = true
	result_label.text = ""
	await _play_reel_reveal(outcome.symbols)
	_show_result(outcome)
	_spinning = false

## Cycles each reel label through random symbol names at a fast, constant
## rate, stopping them one at a time (see REEL_STOP_TIMES) on the machine's
## real rolled symbol with a little landing bounce -- purely a reveal
## animation over an already-fixed `symbols` result, not new randomness.
func _play_reel_reveal(symbols: Array) -> void:
	var symbol_pool: Array = _tracked_machine.SYMBOLS
	var elapsed := 0.0
	var stopped := [false, false, false]
	while stopped.count(false) > 0:
		await get_tree().create_timer(SPIN_CYCLE_INTERVAL).timeout
		elapsed += SPIN_CYCLE_INTERVAL
		for i in reel_labels.size():
			if stopped[i]:
				continue
			if elapsed >= REEL_STOP_TIMES[i]:
				stopped[i] = true
				reel_labels[i].text = String(symbols[i]).capitalize()
				_bounce_reel(reel_labels[i])
			else:
				reel_labels[i].text = String(symbol_pool.pick_random()).capitalize()

## Pops `label` briefly oversized then settles back to normal scale --
## sells the "reel landing" moment beyond just the text changing. Pivots
## around its own center (rather than the default top-left corner) so it
## reads as a genuine pop instead of a lopsided stretch.
func _bounce_reel(label: Label) -> void:
	label.pivot_offset = label.size / 2.0
	label.scale = Vector2(1.35, 1.35)
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), REEL_LAND_BOUNCE_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Shows the final win/lose message once every reel has landed -- a bigger,
## gold, pop-scaled callout for any win (a distinct "JACKPOT!" prefix for
## the rare 3-jackpot outcome, see SlotMachine.spin's is_jackpot flag) versus
## a plain grey line for a loss.
func _show_result(outcome: Dictionary) -> void:
	if outcome.payout.is_empty():
		result_label.text = "No win -- try again!"
		result_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		return

	var parts: Array = []
	for resource_type in outcome.payout.keys():
		parts.append("+%d %s" % [outcome.payout[resource_type], String(resource_type).capitalize()])
	var prefix := "JACKPOT! " if outcome.get("is_jackpot", false) else "You won "
	result_label.text = prefix + ", ".join(parts) + "!"
	result_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))

	result_label.pivot_offset = result_label.size / 2.0
	result_label.scale = Vector2(0.7, 0.7)
	var pulse := create_tween()
	pulse.tween_property(result_label, "scale", Vector2(1.0, 1.0), RESULT_POP_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Godot per-frame hook: keeps the Spin button's greyed-out state current as
## the stockpile changes (skipped entirely mid-reveal so it doesn't fight
## the button's own "spinning" disabled state), and auto-closes if the
## tracked machine was somehow freed out from under this panel.
func _process(_delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(_tracked_machine):
		close_panel()
		return
	if not _spinning:
		_refresh()

func _refresh() -> void:
	spin_button.disabled = not _tracked_machine.can_afford_spin()
	spin_button.text = "Spin (%d wood)" % _tracked_machine.SPIN_COST
