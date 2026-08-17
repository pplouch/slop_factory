extends CanvasLayer
## Always-on-screen resource/selection readout in the top-left corner.
## Reacts to GameManager's signals (Observer pattern) rather than polling
## resource totals every frame -- Population is the one exception (see
## _process), since it changes for reasons no single GameManager signal
## covers (a blob hired/freely spawned/dying in combat, a House finishing
## construction).

@onready var wood_label: Label = $Panel/HBox/WoodLabel
@onready var stone_label: Label = $Panel/HBox/StoneLabel
@onready var planks_label: Label = $Panel/HBox/PlanksLabel
@onready var knowledge_label: Label = $Panel/HBox/KnowledgeLabel
@onready var population_label: Label = $Panel/HBox/PopulationLabel
@onready var day_label: Label = $Panel/HBox/DayLabel
@onready var selected_label: Label = $Panel/HBox/SelectedLabel
@onready var end_run_button: Button = $EndRunButton

## Fired when the player confirms ending the current run (see
## end_run_button's two-step confirm below) -- World listens, banks
## MetaProgression prestige points for how far this run got, and returns to
## MainMenu (see feature backlog: main menu + meta-progression).
signal end_run_requested

var _last_population_text := ""
var _last_day_shown := 0

const END_RUN_CONFIRM_WINDOW := 4.0
var _end_run_armed := false
var _end_run_arm_elapsed := 0.0


## Godot lifecycle hook: subscribes to resource changes and seeds the
## labels with whatever GameManager already holds (relevant if this HUD is
## ever instanced after the game has already collected something).
func _ready() -> void:
	GameManager.resource_changed.connect(_on_resource_changed)
	_on_resource_changed("wood", GameManager.get_resource("wood"))
	_on_resource_changed("stone", GameManager.get_resource("stone"))
	_on_resource_changed("planks", GameManager.get_resource("planks"))
	_on_resource_changed("knowledge", GameManager.get_resource("knowledge"))
	end_run_button.pressed.connect(_on_end_run_pressed)

## Godot per-frame hook: keeps the Population readout current (see class
## doc for why this one stat is polled instead of signal-driven). Only
## touches the label (and its punch cue) when the text actually changed,
## so this doesn't spam a pulse every single frame while population is stable.
func _process(delta: float) -> void:
	var text := "Population: %d/%d" % [GameManager.get_current_population(), GameManager.get_population_cap()]
	if text != _last_population_text:
		_last_population_text = text
		population_label.text = text
		_punch(population_label)

	if _end_run_armed:
		_end_run_arm_elapsed += delta
		if _end_run_arm_elapsed >= END_RUN_CONFIRM_WINDOW:
			_disarm_end_run()

## Signal handler for GameManager.resource_changed: updates the matching
## label's text and gives it a little "punch" pulse so the player notices
## the stockpile actually moved.
func _on_resource_changed(resource_type: String, total: int) -> void:
	match resource_type:
		"wood":
			wood_label.text = "Wood: %d" % total
			_punch(wood_label)
		"stone":
			stone_label.text = "Stone: %d" % total
			_punch(stone_label)
		"planks":
			planks_label.text = "Planks: %d" % total
			_punch(planks_label)
		"knowledge":
			knowledge_label.text = "Knowledge: %d" % total
			_punch(knowledge_label)

## Called by World whenever the blob selection changes, to keep the
## "Selected: N" readout current.
func set_selected_count(n: int) -> void:
	selected_label.text = "Selected: %d" % n

## Called by World every frame with the current DayNightManager reading --
## only touches the label (and its punch cue) when the day number actually
## ticks over, same "don't spam a pulse every frame" guard set_selected_count's
## sibling _process(population) uses, since this would otherwise run every
## single frame all game long. "(Night)" is appended while
## DayNightManager.is_night() is true, cleared once day breaks again.
func set_day_info(day: int, is_night: bool) -> void:
	var text := "Day %d%s" % [day, " (Night)" if is_night else ""]
	if day != _last_day_shown:
		_last_day_shown = day
		_punch(day_label)
	day_label.text = text

## Button handler for End Run -- a two-step confirm (see OptionsPanel's own
## Reset button for the identical shape) since this ends the current run
## and returns to MainMenu, rather than an in-place action a misclick could
## just undo. The first press arms it and relabels the button as a
## confirmation prompt; a second press within END_RUN_CONFIRM_WINDOW
## actually fires end_run_requested for World to handle (see feature
## backlog: main menu + meta-progression).
func _on_end_run_pressed() -> void:
	if not _end_run_armed:
		_end_run_armed = true
		_end_run_arm_elapsed = 0.0
		end_run_button.text = "Are you sure? Click again"
		return
	end_run_requested.emit()

func _disarm_end_run() -> void:
	_end_run_armed = false
	end_run_button.text = "End Run"

## Briefly scales `label` up then eases it back to normal size, used as a
## lightweight "this value just changed" cue.
func _punch(label: Label) -> void:
	label.scale = Vector2(1.35, 1.35)
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
