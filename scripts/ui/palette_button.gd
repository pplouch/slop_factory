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
	title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title)

	if description != "":
		var body := Label.new()
		body.text = description
		body.add_theme_font_size_override("font_size", 11)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(body)

	var cost_label := Label.new()
	cost_label.text = "Cost: %d %s" % [cost, cost_resource.capitalize()]
	var affordable: bool = GameManager.can_afford(cost_resource, cost)
	cost_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0) if affordable else Color(1.0, 0.3, 0.3))
	vbox.add_child(cost_label)

	return panel
