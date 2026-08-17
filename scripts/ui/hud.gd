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
@onready var selected_label: Label = $Panel/HBox/SelectedLabel

var _last_population_text := ""


## Godot lifecycle hook: subscribes to resource changes and seeds the
## labels with whatever GameManager already holds (relevant if this HUD is
## ever instanced after the game has already collected something).
func _ready() -> void:
	GameManager.resource_changed.connect(_on_resource_changed)
	_on_resource_changed("wood", GameManager.get_resource("wood"))
	_on_resource_changed("stone", GameManager.get_resource("stone"))
	_on_resource_changed("planks", GameManager.get_resource("planks"))
	_on_resource_changed("knowledge", GameManager.get_resource("knowledge"))

## Godot per-frame hook: keeps the Population readout current (see class
## doc for why this one stat is polled instead of signal-driven). Only
## touches the label (and its punch cue) when the text actually changed,
## so this doesn't spam a pulse every single frame while population is stable.
func _process(_delta: float) -> void:
	var text := "Population: %d/%d" % [GameManager.get_current_population(), GameManager.get_population_cap()]
	if text != _last_population_text:
		_last_population_text = text
		population_label.text = text
		_punch(population_label)

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

## Briefly scales `label` up then eases it back to normal size, used as a
## lightweight "this value just changed" cue.
func _punch(label: Label) -> void:
	label.scale = Vector2(1.35, 1.35)
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
