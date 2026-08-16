extends CanvasLayer
## Small popup showing a clicked enemy's basic stats -- opened by
## left-clicking any node in the "enemies" group (see
## SelectionManager.handle_click_select), closed by the X button or by
## clicking anywhere else (the dimmed backdrop swallows the click first,
## same pattern as ResourceInfoPanel/BuildingMenu's close-on-outside-click).
##
## Refreshes live while open since combat drains the tracked enemy's health
## in real time; auto-closes if the enemy dies/is freed.

@onready var name_label: Label = $Panel/VBox/NameLabel
@onready var health_label: Label = $Panel/VBox/HealthLabel
@onready var attack_label: Label = $Panel/VBox/AttackLabel
@onready var speed_label: Label = $Panel/VBox/SpeedLabel
@onready var close_button: Button = $CloseButton
@onready var backdrop: ColorRect = $Backdrop

var _tracked_enemy: Node = null


## Godot lifecycle hook: starts hidden.
func _ready() -> void:
	visible = false
	close_button.pressed.connect(close_panel)
	backdrop.gui_input.connect(_on_backdrop_gui_input)

func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()

## Opens the panel for `enemy` and starts tracking it live.
func open_for(enemy: Node) -> void:
	_tracked_enemy = enemy
	visible = true
	_refresh()

func close_panel() -> void:
	visible = false
	_tracked_enemy = null

## Godot per-frame hook: keeps health live while open, auto-closing if the
## tracked enemy died-and-was-freed.
func _process(_delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(_tracked_enemy):
		close_panel()
		return
	_refresh()

func _refresh() -> void:
	var enemy := _tracked_enemy
	var kind := EnemyKinds.get_kind(enemy.kind_id)
	name_label.text = kind.display_name
	health_label.text = "Health: %d / %d" % [int(round(enemy.health)), int(round(enemy.max_health))]
	attack_label.text = "Attack: %d" % int(round(enemy.attack_power))
	speed_label.text = "Speed: %.1f" % enemy.move_speed
