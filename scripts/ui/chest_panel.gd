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

@onready var contents_label: Label = $Panel/VBox/ContentsLabel
@onready var open_button: Button = $Panel/VBox/OpenButton
@onready var close_button: Button = $CloseButton
@onready var backdrop: ColorRect = $Backdrop

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

## Opens the panel for `chest` and lists its rolled contents.
func open_for(chest: Node) -> void:
	_tracked_chest = chest
	visible = true
	var parts: Array = []
	for resource_type in chest.loot.keys():
		parts.append("%s: %d" % [String(resource_type).capitalize(), chest.loot[resource_type]])
	contents_label.text = "\n".join(parts) if not parts.is_empty() else "Empty"

func close_panel() -> void:
	visible = false
	_tracked_chest = null

## Button handler for Open: grants the loot (see Chest.open, which also
## frees the chest) and closes the panel.
func _on_open_pressed() -> void:
	if is_instance_valid(_tracked_chest):
		_tracked_chest.open()
	close_panel()

## Godot per-frame hook: auto-closes if the tracked chest was somehow freed
## out from under this panel (e.g. demolished by another system) without
## going through the normal Open button.
func _process(_delta: float) -> void:
	if visible and not is_instance_valid(_tracked_chest):
		close_panel()
