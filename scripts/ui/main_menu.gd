extends Control
## The game's new starting scene (see feature backlog: "Add a Main Menu
## (Start / Upgrades / Options / Quit) as the new starting scene"). Start
## loads the actual gameplay scene; Upgrades/Options open their own
## sub-panels (scripts/ui/upgrades_panel.gd, options_panel.gd) as overlays
## on top of this same scene rather than separate scenes of their own,
## since neither needs anything from World and this avoids an extra
## scene-load round trip just to browse a menu.

const WORLD_SCENE_PATH := "res://scenes/world/world.tscn"
## See feature request: "add a new scene accessible from the main menu:
## debug scene" -- a flat, non-chunked scene pre-populated with a whole
## "factory town" (every building kind, several belt/wall-and-gate
## configurations, a scattered crowd of blobs) for eyeballing/interacting
## with new meshes and configurations without waiting on real progression.
const DEBUG_SCENE_PATH := "res://scenes/world/debug_scene.tscn"

@onready var start_button: Button = $VBox/StartButton
@onready var upgrades_button: Button = $VBox/UpgradesButton
@onready var options_button: Button = $VBox/OptionsButton
@onready var debug_scene_button: Button = $VBox/DebugSceneButton
@onready var quit_button: Button = $VBox/QuitButton
@onready var upgrades_panel = $UpgradesPanel
@onready var options_panel = $OptionsPanel
@onready var prestige_label: Label = $PrestigeLabel


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	upgrades_button.pressed.connect(upgrades_panel.open_panel)
	options_button.pressed.connect(options_panel.open_panel)
	debug_scene_button.pressed.connect(_on_debug_scene_pressed)
	quit_button.pressed.connect(get_tree().quit)
	MetaProgression.changed.connect(_refresh_prestige_label)
	_refresh_prestige_label()

## Keeps the corner readout current -- the only feedback the player gets
## right on landing back at this menu that a just-ended run's points
## actually banked (see World._on_end_run_requested), since MetaProgression
## itself has no dedicated "you earned N points" popup of its own.
func _refresh_prestige_label() -> void:
	prestige_label.text = "Prestige Points: %d" % MetaProgression.prestige_points

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE_PATH)

func _on_debug_scene_pressed() -> void:
	get_tree().change_scene_to_file(DEBUG_SCENE_PATH)
