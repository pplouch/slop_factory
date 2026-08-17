extends CanvasLayer
## Standalone tech-tree/unlock panel, toggled by a button placed right next
## to Build Mode's (see scenes/ui/tech_tree_panel.tscn) -- the "Unlock
## Buildings" section used to live inside BuildingMenu, only reachable by
## clicking an already-built Town Hall; pulled out into its own always-
## available panel (same toggle-a-corner-panel shape BuildPalette uses,
## rather than BuildingMenu's clicked-object modal, since this isn't about
## any one clicked thing) and switched from spending wood to a new
## "knowledge" currency, produced by ResearchCenter, so building tiers have
## their own economy distinct from what an individual instance costs to
## place/upgrade.
##
## Rows are built once from BuildingKinds data and never rebuilt, just
## shown/hidden/relabeled on refresh (same shape BuildingMenu's old unlock
## section used) -- adding a new building kind needs no changes here.

@onready var toggle_button: Button = $ToggleButton
@onready var panel: PanelContainer = $Panel
@onready var knowledge_label: Label = $Panel/VBox/KnowledgeLabel
@onready var rows_container: VBoxContainer = $Panel/VBox/Scroll/Rows

var _labels: Dictionary = {}
var _buttons: Dictionary = {}
var _rows: Dictionary = {}


## Godot lifecycle hook: starts collapsed, builds every row from
## BuildingKinds, and subscribes to GameManager so knowledge totals/unlock
## state stay current without polling.
func _ready() -> void:
	panel.visible = false
	toggle_button.pressed.connect(_toggle)
	_build_rows()
	GameManager.resource_changed.connect(func(_type, _total): _refresh())
	GameManager.building_unlocked.connect(func(_id): _refresh())
	_refresh()

## Shows/hides the panel; refreshes on open so it's never showing stale
## affordability from while it was closed.
func _toggle() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		_refresh()

## Creates one row (label + button) per BuildingKinds entry that actually
## needs unlocking (unlock_cost > 0 -- Town Hall/Wall/Belt are seeded
## unlocked from the start and have no row at all, since there's nothing to
## buy). A row hides itself once its building is unlocked (see _refresh)
## rather than being removed, so rebuilding rows from scratch is never needed.
func _build_rows() -> void:
	for building_id in BuildingKinds.get_ordered_ids():
		var kind = BuildingKinds.get_kind(building_id)
		if kind.unlock_cost <= 0:
			continue

		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var button := Button.new()
		button.pressed.connect(func(): GameManager.try_unlock_building(building_id))

		var row := HBoxContainer.new()
		row.add_child(label)
		row.add_child(button)
		rows_container.add_child(row)

		_labels[building_id] = label
		_buttons[building_id] = button
		_rows[building_id] = row

## Refreshes the knowledge readout and every unlock row's visibility/label/
## affordability.
func _refresh() -> void:
	knowledge_label.text = "Knowledge: %d" % GameManager.get_resource("knowledge")
	for building_id in _rows.keys():
		var unlocked: bool = GameManager.is_building_unlocked(building_id)
		_rows[building_id].visible = not unlocked
		if unlocked:
			continue
		var kind = BuildingKinds.get_kind(building_id)
		var prereq_ok: bool = kind.requires == "" or GameManager.is_building_unlocked(kind.requires)
		var label_text: String = kind.display_name
		if not prereq_ok:
			label_text += " (needs %s)" % BuildingKinds.get_kind(kind.requires).display_name
		_labels[building_id].text = label_text
		_buttons[building_id].text = "Unlock (%d knowledge)" % kind.unlock_cost
		_buttons[building_id].disabled = not GameManager.can_unlock_building(building_id)
