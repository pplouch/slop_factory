extends CanvasLayer
## Small popup showing a clicked resource node's remaining amount --
## opened by left-clicking any node in the "resource_nodes" group (see
## World._handle_click_select), closed by the X button or by clicking
## anywhere else (the dimmed backdrop swallows the click first, same
## pattern as BuildingMenu's close-on-outside-click).
##
## Refreshes live while open since harvesting drains the tracked node's
## amount in real time; auto-closes if the node depletes/is freed.

@onready var name_label: Label = $Panel/VBox/NameLabel
@onready var amount_label: Label = $Panel/VBox/AmountLabel
@onready var close_button: Button = $CloseButton
@onready var backdrop: ColorRect = $Backdrop

var _tracked_node: Node = null


## Godot lifecycle hook: starts hidden.
func _ready() -> void:
	visible = false
	close_button.pressed.connect(close_panel)
	backdrop.gui_input.connect(_on_backdrop_gui_input)

func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()

## Opens the panel for `node` (a ResourceNode/Animal) and starts tracking
## it live.
func open_for(node: Node) -> void:
	_tracked_node = node
	visible = true
	_refresh()

func close_panel() -> void:
	visible = false
	_tracked_node = null

## Godot per-frame hook: keeps the amount live while open, auto-closing if
## the tracked node depleted-and-was-freed or is otherwise gone.
func _process(_delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(_tracked_node):
		close_panel()
		return
	_refresh()

func _refresh() -> void:
	var node = _tracked_node
	name_label.text = String(node.resource_type).capitalize()
	amount_label.text = "Remaining: %d / %d" % [node.amount, node.max_amount]
