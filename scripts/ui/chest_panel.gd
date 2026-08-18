extends CanvasLayer
## Popup shown when the player clicks a Chest -- lists its contents and
## lets the player claim them via an Open button, closed by the X button or
## by clicking anywhere else (the dimmed backdrop swallows the click first,
## same pattern as ResourceInfoPanel/EnemyInfoPanel/BuildingMenu's close-
## on-outside-click).
##
## Unlike ResourceInfoPanel (which keeps live-refreshing a depleting
## amount), a Chest is a one-shot: opening it grants the whole loot table
## at once and removes the chest for good (see Chest.open), so this panel
## just closes itself right afterward instead of continuing to track
## anything.

@onready var loot_list: VBoxContainer = $Panel/VBox/LootList
@onready var open_button: Button = $Panel/VBox/OpenButton
@onready var close_button: Button = $CloseButton
@onready var backdrop: ColorRect = $Backdrop

## How long each loot line waits (staggered by index) before popping in, and
## how long the panel lingers on "Claimed!" before closing itself -- purely
## cosmetic timing so opening a chest reads as a real reveal instead of an
## instant menu-close (see feature request: "improve Chest UI... filled
## with VFX and animation").
const LOOT_LINE_STAGGER := 0.1
const LOOT_LINE_FADE_DURATION := 0.25
const CLAIMED_LINGER_DURATION := 0.45

var _tracked_chest: Node = null


## Godot lifecycle hook: starts hidden.
func _ready() -> void:
	visible = false
	close_button.pressed.connect(close_panel)
	backdrop.gui_input.connect(_on_backdrop_gui_input)
	open_button.pressed.connect(_on_open_pressed)

func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()

## Opens the panel for `chest`, resets the Open button back to its normal
## state (in case a previous chest was closed mid-"Claimed!" linger -- see
## _on_open_pressed), and lists its rolled contents as individually
## color-coded, staggered pop-in lines rather than one static multi-line
## label.
func open_for(chest: Node) -> void:
	_tracked_chest = chest
	visible = true
	open_button.disabled = false
	open_button.text = "Open"
	open_button.modulate = Color(1, 1, 1)

	for child in loot_list.get_children():
		child.queue_free()
	var entries: Array = chest.loot.keys()
	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Empty"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		loot_list.add_child(empty_label)
		return
	for i in entries.size():
		var resource_type: String = entries[i]
		var label := Label.new()
		label.text = "%s: %d" % [String(resource_type).capitalize(), chest.loot[resource_type]]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Effects.resource_color(resource_type))
		label.modulate.a = 0.0
		loot_list.add_child(label)
		var reveal := create_tween()
		reveal.tween_interval(i * LOOT_LINE_STAGGER)
		reveal.tween_property(label, "modulate:a", 1.0, LOOT_LINE_FADE_DURATION)

func close_panel() -> void:
	visible = false
	_tracked_chest = null

## Button handler for Open: grants the loot (see Chest.open, which plays its
## own lid/particle/glow flourish and frees the chest once that's done),
## then lingers on a brief "Claimed!" flash before closing this panel
## instead of vanishing the instant the button is pressed.
func _on_open_pressed() -> void:
	if not is_instance_valid(_tracked_chest):
		return
	_tracked_chest.open()
	open_button.disabled = true
	open_button.text = "Claimed!"
	var flash := create_tween()
	flash.tween_property(open_button, "modulate", Color(1.4, 1.2, 0.6), 0.12)
	flash.tween_property(open_button, "modulate", Color(1, 1, 1), 0.25)
	await get_tree().create_timer(CLAIMED_LINGER_DURATION).timeout
	close_panel()

## Godot per-frame hook: auto-closes if the tracked chest was somehow freed
## out from under this panel (e.g. demolished by another system) without
## going through the normal Open button.
func _process(_delta: float) -> void:
	if visible and not is_instance_valid(_tracked_chest):
		close_panel()
