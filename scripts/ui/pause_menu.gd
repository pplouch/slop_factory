extends CanvasLayer
## In-game pause overlay. Kept on PROCESS_MODE_ALWAYS so Escape and the
## buttons remain responsive while the rest of the scene tree is paused.

signal return_to_menu_requested

@onready var resume_button: Button = $Panel/VBox/ResumeButton
@onready var options_button: Button = $Panel/VBox/OptionsButton
@onready var menu_button: Button = $Panel/VBox/MenuButton
@onready var options_panel = $OptionsPanel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	options_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	resume_button.pressed.connect(resume)
	options_button.pressed.connect(options_panel.open_panel)
	menu_button.pressed.connect(_on_menu_pressed)

func pause() -> void:
	get_tree().paused = true
	visible = true

func resume() -> void:
	options_panel.close_panel()
	visible = false
	get_tree().paused = false

func toggle() -> void:
	if visible:
		resume()
	else:
		pause()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if options_panel.visible:
			options_panel.close_panel()
		else:
			toggle()
		get_viewport().set_input_as_handled()

func _on_menu_pressed() -> void:
	options_panel.close_panel()
	visible = false
	get_tree().paused = false
	return_to_menu_requested.emit()
