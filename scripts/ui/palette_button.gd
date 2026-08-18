class_name PaletteButton
extends Button
## A small square build-palette icon button (see BuildPalette) whose hover
## tooltip is a custom panel instead of the default plain-text one, so the
## resource-cost line can be colored red when the player can't currently
## afford it (see feature backlog: "small squares for each building, with a
## tooltip containing all the building details when hovering, resources
## needed shown in red if the player doesn't have the necessary amount").
##
## The engine calls _make_custom_tooltip fresh every time a tooltip is
## about to actually be shown (not once up front), so the affordability
## check in there is always current at that moment rather than needing
## separate live upkeep the way e.g. BuildingMenu's rows do.

var kind_id: String = ""
var display_name: String = ""
## Extra descriptive line(s), e.g. a factory piece's recipe or placement
## restriction, or a building's port/durability/build-time summary --
## empty is fine, the tooltip just omits that line.
var description: String = ""
var cost: int = 0
var cost_resource: String = ""

const NAME_LABEL_FONT_SIZE := 11
const NAME_LABEL_OUTLINE_SIZE := 4


## Godot lifecycle hook: layers a small centered name label over the icon
## swatch -- there's no real icon art yet (see feature request: "add the
## name of the building in the square, since there are not icons yet"), so
## the name is the only way to tell entries apart at a glance without
## hovering for the full tooltip. `display_name` is already set by
## BuildPalette._add_button before this button enters the tree (see
## CLAUDE.md: "set @export properties before add_child()" -- the same
## ordering requirement applies to any plain var a _ready() reads once on
## tree-entry). A dark outline keeps the label legible regardless of the
## swatch's own color; mouse_filter is set to IGNORE so the label never
## steals the click meant for the button underneath it.
func _ready() -> void:
	var label := Label.new()
	label.text = display_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.clip_contents = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", NAME_LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", NAME_LABEL_OUTLINE_SIZE)
	add_child(label)


## Builds a small panel (title, optional description, cost line colored red
## when unaffordable) in place of the default plain-text tooltip.
func _make_custom_tooltip(_for_text: String) -> Object:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(210, 0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = display_name
	title.add_theme_font_size_override("font_size", 17)
	vbox.add_child(title)

	if description != "":
		var body := Label.new()
		body.text = description
		body.add_theme_font_size_override("font_size", 13)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(body)

	var cost_label := Label.new()
	cost_label.text = "Cost: %d %s" % [cost, cost_resource.capitalize()]
	var affordable: bool = GameManager.can_afford(cost_resource, cost)
	cost_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0) if affordable else Color(1.0, 0.3, 0.3))
	vbox.add_child(cost_label)

	return panel
