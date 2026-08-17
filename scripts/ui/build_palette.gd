extends CanvasLayer
## The always-visible "Build Mode" toggle button plus the structure palette
## that appears next to it once build mode is active. Purely a view: it
## reports button presses via signals and lets World tell it what to show
## (World owns all placement logic, grid state, and cost/validity checks).
##
## Every entry (the 3 fixed factory pieces that never joined the tech tree,
## plus every BuildingKinds entry -- Town Hall, Storage Depot, ..., and
## Wall/Belt/Pipe/Road too, see scripts/core/linkable_building.gd) is a
## small square icon button laid out in a shared GridContainer inside a
## ScrollContainer, rather than the one-row-per-kind vertical list this used
## to be -- once every building kind is unlocked, that list overflowed the
## palette's fixed-height panel with no way to scroll, leaving the bottom
## rows unreachable (see feature backlog: "the build menu doesn't scroll so
## bottom buttons cannot be reached"). Full details (name, description,
## cost -- colored red when unaffordable) show in a hover tooltip instead of
## as button text, via PaletteButton's own custom tooltip (see
## scripts/ui/palette_button.gd).
##
## BuildingKinds entries are built dynamically and only shown once
## GameManager reports them unlocked -- see _refresh_building_buttons,
## re-run whenever GameManager.building_unlocked fires so a freshly-
## unlocked building appears immediately without reopening anything.
##
## Demolishing isn't a palette selection at all -- it's a right-click on an
## existing structure while build mode is active (see World._demolish_at).

signal toggle_requested
signal kind_selected(kind_id: String)

@onready var toggle_button: Button = $ToggleButton
@onready var palette_panel: PanelContainer = $PalettePanel
@onready var grid: GridContainer = $PalettePanel/VBox/Scroll/Grid

const SELECTED_TINT := Color(1.0, 0.92, 0.5)
const NORMAL_TINT := Color(1, 1, 1)
const BUTTON_SIZE := Vector2(46.0, 46.0)

# Display colors for the 3 fixed factory pieces (not BuildingKinds entries,
# so they have no kind.display_color to read) -- matching each one's own
# scene's dominant mesh material, same convention BuildingKinds.Kind uses.
const EXTRACTOR_COLOR := Color(0.45, 0.42, 0.4)
const PROCESSOR_COLOR := Color(0.35, 0.38, 0.42)
const WATER_EXTRACTOR_COLOR := Color(0.3, 0.55, 0.75)

# id -> {name, color, cost, cost_resource, description} for the 3 pieces
# that never joined the tech tree, in fixed display order.
const FACTORY_PIECES := {
	"extractor": {
		"name": "Extractor", "color": EXTRACTOR_COLOR, "cost": 25, "cost_resource": "wood",
		"description": "Automatically harvests a linked resource node onto its output belt. No blob required.",
	},
	"processor": {
		"name": "Processor", "color": PROCESSOR_COLOR, "cost": 30, "cost_resource": "wood",
		"description": "Converts 2 wood into 1 plank over time.",
	},
	"water_extractor": {
		"name": "Water Extractor", "color": WATER_EXTRACTOR_COLOR, "cost": 25, "cost_resource": "wood",
		"description": "Draws water onto its output belt. Can only be placed on water tiles.",
	},
}

var _building_buttons: Dictionary = {}


## Godot lifecycle hook: starts with the palette collapsed, builds one
## square icon button per palette entry, and subscribes to unlock/resource
## changes so visibility and tooltip affordability stay current.
func _ready() -> void:
	palette_panel.visible = false
	toggle_button.pressed.connect(func(): toggle_requested.emit())
	_build_buttons()
	GameManager.building_unlocked.connect(func(_id): _refresh_building_buttons())
	_refresh_building_buttons()

## Creates one PaletteButton per palette entry -- the 3 fixed factory
## pieces first, then every BuildingKinds entry (hidden until unlocked, see
## _refresh_building_buttons) -- all in the one shared grid.
func _build_buttons() -> void:
	for kind_id in FACTORY_PIECES.keys():
		var data: Dictionary = FACTORY_PIECES[kind_id]
		_add_button(kind_id, data["name"], data["color"], data["cost"], data["cost_resource"], data["description"])

	for building_id in BuildingKinds.get_ordered_ids():
		var kind = BuildingKinds.get_kind(building_id)
		var button := _add_button(building_id, kind.display_name, kind.display_color, kind.build_cost, kind.build_cost_resource, _building_description(kind))
		_building_buttons[building_id] = button

## Building-kind tooltip description built from data BuildingMenu's own
## "This Building" section already surfaces (ports/durability/build time)
## -- BuildingKinds has no separate free-text description field of its own,
## and this covers every entry uniformly without needing one.
func _building_description(kind) -> String:
	var input_desc: String = "none" if kind.input_ports.is_empty() else str(kind.input_ports.size())
	var output_desc: String = "none" if kind.output_ports.is_empty() else str(kind.output_ports.size())
	return "Inputs: %s   Outputs: %s\nDurability: %d\nBuild time: %ds labor" % [input_desc, output_desc, kind.max_durability, int(kind.build_labor)]

## Builds one square icon button, wires it to emit kind_selected, and adds
## it to the grid.
func _add_button(kind_id: String, display_name: String, color: Color, cost: int, cost_resource: String, description: String) -> PaletteButton:
	var button := PaletteButton.new()
	button.custom_minimum_size = BUTTON_SIZE
	button.icon = Effects.make_swatch_texture(color)
	button.expand_icon = true
	button.kind_id = kind_id
	button.display_name = display_name
	button.description = description
	button.cost = cost
	button.cost_resource = cost_resource
	button.pressed.connect(func(): kind_selected.emit(kind_id))
	grid.add_child(button)
	return button

## Shows/hides each building button to match current unlock state.
func _refresh_building_buttons() -> void:
	for building_id in _building_buttons.keys():
		_building_buttons[building_id].visible = GameManager.is_building_unlocked(building_id)

## Shows/hides the structure palette and relabels the toggle button to
## reflect the current build-mode state.
func set_active(active: bool) -> void:
	palette_panel.visible = active
	toggle_button.text = "Exit Build Mode" if active else "Build Mode"

## Highlights whichever palette button corresponds to the currently
## selected structure kind.
func set_selected_kind(kind_id: String) -> void:
	for child in grid.get_children():
		if child is PaletteButton:
			child.modulate = SELECTED_TINT if child.kind_id == kind_id else NORMAL_TINT
