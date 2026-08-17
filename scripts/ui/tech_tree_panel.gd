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
## Two independent sections, Buildings and Blob Kinds, each built once from
## its own registry data and never rebuilt, just shown/hidden/relabeled on
## refresh -- adding a new building or blob kind needs no changes here.
## Kept as two near-identical row-building/refresh blocks rather than one
## generic helper parameterized over both registries -- BuildingKinds.Kind
## and BlobKinds.Kind are different shapes with different unlock functions
## on GameManager, and at just two call sites the duplication reads more
## plainly than a Callable-juggling abstraction would.

@onready var toggle_button: Button = $ToggleButton
@onready var panel: PanelContainer = $Panel
@onready var knowledge_label: Label = $Panel/VBox/KnowledgeLabel
@onready var building_rows_container: VBoxContainer = $Panel/VBox/Scroll/Content/BuildingRows
@onready var blob_rows_container: VBoxContainer = $Panel/VBox/Scroll/Content/BlobRows

var _building_labels: Dictionary = {}
var _building_buttons: Dictionary = {}
var _building_rows: Dictionary = {}

var _blob_labels: Dictionary = {}
var _blob_buttons: Dictionary = {}
var _blob_rows: Dictionary = {}


## Godot lifecycle hook: starts collapsed, builds every row from
## BuildingKinds/BlobKinds, and subscribes to GameManager so knowledge
## totals/unlock state stay current without polling.
func _ready() -> void:
	panel.visible = false
	toggle_button.pressed.connect(_toggle)
	_build_building_rows()
	_build_blob_rows()
	GameManager.resource_changed.connect(func(_type, _total): _refresh())
	GameManager.building_unlocked.connect(func(_id): _refresh())
	GameManager.blob_kind_unlocked.connect(func(_id): _refresh())
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
func _build_building_rows() -> void:
	for building_id in BuildingKinds.get_ordered_ids():
		var kind = BuildingKinds.get_kind(building_id)
		if kind.unlock_cost <= 0:
			continue

		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var button := Button.new()
		button.icon = Effects.make_swatch_texture(kind.display_color)
		button.pressed.connect(func(): GameManager.try_unlock_building(building_id))

		var row := HBoxContainer.new()
		row.add_child(label)
		row.add_child(button)
		building_rows_container.add_child(row)

		_building_labels[building_id] = label
		_building_buttons[building_id] = button
		_building_rows[building_id] = row

## Blob-kind counterpart to _build_building_rows -- same shape, one row per
## BlobKinds entry with a nonzero unlock_cost ("worker" is seeded unlocked
## and has no row at all, same reasoning as Town Hall/Wall/Belt above).
func _build_blob_rows() -> void:
	for blob_kind_id in BlobKinds.get_ordered_ids():
		var kind = BlobKinds.get_kind(blob_kind_id)
		if kind.unlock_cost <= 0:
			continue

		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var button := Button.new()
		button.icon = Effects.make_swatch_texture(kind.body_color())
		button.pressed.connect(func(): GameManager.try_unlock_blob_kind(blob_kind_id))

		var row := HBoxContainer.new()
		row.add_child(label)
		row.add_child(button)
		blob_rows_container.add_child(row)

		_blob_labels[blob_kind_id] = label
		_blob_buttons[blob_kind_id] = button
		_blob_rows[blob_kind_id] = row

## Refreshes the knowledge readout and every unlock row's visibility/label/
## affordability, for both the Buildings and Blob Kinds sections.
func _refresh() -> void:
	knowledge_label.text = "Knowledge: %d" % GameManager.get_resource("knowledge")

	for building_id in _building_rows.keys():
		var unlocked: bool = GameManager.is_building_unlocked(building_id)
		_building_rows[building_id].visible = not unlocked
		if unlocked:
			continue
		var kind = BuildingKinds.get_kind(building_id)
		var prereq_ok: bool = kind.requires == "" or GameManager.is_building_unlocked(kind.requires)
		var label_text: String = kind.display_name
		if not prereq_ok:
			label_text += " (needs %s)" % BuildingKinds.get_kind(kind.requires).display_name
		_building_labels[building_id].text = label_text
		_building_buttons[building_id].text = "Unlock (%d knowledge)" % kind.unlock_cost
		_building_buttons[building_id].disabled = not GameManager.can_unlock_building(building_id)

	for blob_kind_id in _blob_rows.keys():
		var unlocked: bool = GameManager.is_blob_kind_unlocked(blob_kind_id)
		_blob_rows[blob_kind_id].visible = not unlocked
		if unlocked:
			continue
		var kind = BlobKinds.get_kind(blob_kind_id)
		var prereq_ok: bool = kind.requires == "" or GameManager.is_blob_kind_unlocked(kind.requires)
		var label_text: String = kind.display_name
		if not prereq_ok:
			label_text += " (needs %s)" % BlobKinds.get_kind(kind.requires).display_name
		_blob_labels[blob_kind_id].text = label_text
		_blob_buttons[blob_kind_id].text = "Unlock (%d knowledge)" % kind.unlock_cost
		_blob_buttons[blob_kind_id].disabled = not GameManager.can_unlock_blob_kind(blob_kind_id)
