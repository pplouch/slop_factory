extends CanvasLayer
## Popup shown when the player clicks a SlotMachine (see the backlog's
## "wanky dandy" mini-game item, and SlotMachine's own header for why this
## specific shape was chosen) -- shows the 3 rolled reel symbols and
## whatever they paid out (see SlotMachine.spin), and can be spun again as
## many times as the player can afford, unlike Chest's one-shot grant.

@onready var reel_label: Label = $Panel/VBox/ReelLabel
@onready var result_label: Label = $Panel/VBox/ResultLabel
@onready var spin_button: Button = $Panel/VBox/SpinButton
@onready var close_button: Button = $CloseButton
@onready var backdrop: ColorRect = $Backdrop

var _tracked_machine: Node = null


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
	reel_label.text = "? | ? | ?"
	result_label.text = ""
	_refresh()

func close_panel() -> void:
	visible = false
	_tracked_machine = null

## Button handler for Spin: asks the tracked machine to actually spin (see
## SlotMachine.spin, which also spends/grants resources) and shows the
## result -- a no-op if the spin failed outright (unaffordable, or the
## machine vanished out from under this panel).
func _on_spin_pressed() -> void:
	if not is_instance_valid(_tracked_machine):
		return
	var outcome: Dictionary = _tracked_machine.spin()
	if outcome.symbols.is_empty():
		return
	var symbol_names: Array = outcome.symbols.map(func(s): return String(s).capitalize())
	reel_label.text = " | ".join(symbol_names)
	if outcome.payout.is_empty():
		result_label.text = "No win -- try again!"
	else:
		var parts: Array = []
		for resource_type in outcome.payout.keys():
			parts.append("+%d %s" % [outcome.payout[resource_type], String(resource_type).capitalize()])
		result_label.text = "You won " + ", ".join(parts) + "!"

## Godot per-frame hook: keeps the Spin button's greyed-out state current
## as the stockpile changes, and auto-closes if the tracked machine was
## somehow freed out from under this panel.
func _process(_delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(_tracked_machine):
		close_panel()
		return
	_refresh()

func _refresh() -> void:
	spin_button.disabled = not _tracked_machine.can_afford_spin()
	spin_button.text = "Spin (%d wood)" % _tracked_machine.SPIN_COST
