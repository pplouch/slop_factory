extends CanvasLayer
## Debug-only panel: instantly spawns a blob or enemy, or tops up the
## stockpile, for testing without needing to grind resources first. Purely
## a view -- World owns what each button actually does.

signal toggle_requested
signal spawn_blob_requested
signal spawn_enemy_requested
signal add_resources_requested
signal toggle_hitboxes_requested
signal toggle_grid_requested
## Fired by the "Clear Fog" button -- reveals the entire tracked map at once.
signal clear_fog_requested
## Fired by one of the 4 time-of-day buttons; `fraction` is 0..1 (see
## DayNightManager.time_of_day_fraction/set_time_fraction).
signal set_time_requested(fraction: float)
## Fired by "Spawn Enemies Near Base" -- see SpawnManager.spawn_enemies_near_base.
signal spawn_enemies_near_base_requested

@onready var toggle_button: Button = $ToggleButton
@onready var panel: PanelContainer = $Panel
@onready var hitboxes_button: Button = $Panel/VBox/ToggleHitboxesButton
@onready var grid_button: Button = $Panel/VBox/ToggleGridButton


## Godot lifecycle hook: starts collapsed and wires each button to emit its
## corresponding signal.
func _ready() -> void:
	panel.visible = false
	toggle_button.pressed.connect(func(): toggle_requested.emit())
	$Panel/VBox/SpawnBlobButton.pressed.connect(func(): spawn_blob_requested.emit())
	$Panel/VBox/SpawnEnemyButton.pressed.connect(func(): spawn_enemy_requested.emit())
	$Panel/VBox/SpawnEnemiesNearBaseButton.pressed.connect(func(): spawn_enemies_near_base_requested.emit())
	$Panel/VBox/AddResourcesButton.pressed.connect(func(): add_resources_requested.emit())
	$Panel/VBox/ClearFogButton.pressed.connect(func(): clear_fog_requested.emit())
	$Panel/VBox/TimeRow/DawnButton.pressed.connect(func(): set_time_requested.emit(0.2))
	$Panel/VBox/TimeRow/NoonButton.pressed.connect(func(): set_time_requested.emit(0.5))
	$Panel/VBox/TimeRow/DuskButton.pressed.connect(func(): set_time_requested.emit(0.8))
	$Panel/VBox/TimeRow/MidnightButton.pressed.connect(func(): set_time_requested.emit(0.0))
	hitboxes_button.pressed.connect(func(): toggle_hitboxes_requested.emit())
	grid_button.pressed.connect(func(): toggle_grid_requested.emit())

## Relabels the hitbox-toggle button to reflect whether the overlay is
## currently on (called by World, which owns the actual on/off state).
func set_hitboxes_active(active: bool) -> void:
	hitboxes_button.text = "Hide Hitboxes" if active else "Show Hitboxes"

## Relabels the grid-toggle button to reflect whether the world grid overlay
## is currently on (called by World, which owns the actual on/off state).
func set_grid_active(active: bool) -> void:
	grid_button.text = "Hide Grid" if active else "Show Grid"

## Shows/hides the debug panel and relabels the toggle button to match.
func set_active(active: bool) -> void:
	panel.visible = active
	toggle_button.text = "Close Debug" if active else "Debug Menu"
