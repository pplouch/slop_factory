extends CanvasLayer
## Popup shown when the player clicks a FriendlyVillage -- lists its rolled
## trade offers (see FriendlyVillage.offers) as one button each. Unlike
## ChestPanel's single one-shot Open button, each offer button here can be
## pressed repeatedly across separate visits, since a village never
## depletes (see FriendlyVillage.try_trade).

@onready var offers_vbox: VBoxContainer = $Panel/VBox/OffersVBox
@onready var close_button: Button = $CloseButton
@onready var backdrop: ColorRect = $Backdrop

var _tracked_village: Node = null


## Godot lifecycle hook: starts hidden.
func _ready() -> void:
	visible = false
	close_button.pressed.connect(close_panel)
	backdrop.gui_input.connect(_on_backdrop_gui_input)

func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()

## Opens the panel for `village` and (re)builds one button per rolled offer.
func open_for(village: Node) -> void:
	_tracked_village = village
	visible = true
	for child in offers_vbox.get_children():
		child.queue_free()
	for i in village.offers.size():
		var offer: Dictionary = village.offers[i]
		var button := Button.new()
		button.text = "Give %d %s -> Receive %d %s" % [offer.give_amount, String(offer.give).capitalize(), offer.receive_amount, String(offer.receive).capitalize()]
		button.pressed.connect(_on_trade_pressed.bind(i))
		offers_vbox.add_child(button)
	_refresh_affordability()

func close_panel() -> void:
	visible = false
	_tracked_village = null

func _on_trade_pressed(index: int) -> void:
	if is_instance_valid(_tracked_village):
		_tracked_village.try_trade(index)

## Godot per-frame hook: keeps each offer button's greyed-out state current
## as the stockpile changes (a trade made just now shouldn't leave a
## suddenly-unaffordable button looking clickable), and auto-closes if the
## tracked village was somehow freed out from under this panel.
func _process(_delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(_tracked_village):
		close_panel()
		return
	_refresh_affordability()

func _refresh_affordability() -> void:
	var buttons := offers_vbox.get_children()
	for i in buttons.size():
		buttons[i].disabled = not _tracked_village.can_afford_offer(i)
