extends CanvasLayer
## The generic modal opened by left-clicking any building (Town Hall,
## Storage Depot, Wall, ...). Every building gets the "This Building"
## section (name/durability/per-instance upgrade+perk/inputs/outputs, read
## from whichever instance was clicked); the account-wide Global Upgrades
## and Hire sections only show for buildings that expose Town-Hall-specific
## capabilities (duck-typed via has_method("hire_blob")), since those
## concepts (spending on a global stat, hiring a blob) don't make sense for
## e.g. a Storage Depot or a Wall. Unlocking new building kinds used to be a
## third such section here (reachable only by clicking the Town Hall) but
## now lives in its own always-available `TechTreePanel` instead (see
## scripts/ui/tech_tree_panel.gd) -- pulled out partly so it doesn't need a
## built Town Hall to check, partly because it now spends a different
## currency (knowledge, not wood) than anything else in this menu.
##
## Every section is built entirely from data rather than hardcoded scene
## nodes: the upgrade rows come from GameManager.UPGRADE_STATS, the hire
## rows come from BlobKinds' registered archetypes. Adding a new stat or
## blob kind therefore needs no changes here or in the .tscn.
##
## Refreshes reactively whenever GameManager's resource/upgrade signals
## fire, rather than polling every frame.

@onready var panel: PanelContainer = $Panel
@onready var vbox: VBoxContainer = $Panel/Scroll/VBox
@onready var this_building_section: VBoxContainer = $Panel/Scroll/VBox/ThisBuildingSection
@onready var name_label: Label = $Panel/Scroll/VBox/ThisBuildingSection/NameLabel
@onready var construction_label: Label = $Panel/Scroll/VBox/ThisBuildingSection/ConstructionLabel
@onready var durability_label: Label = $Panel/Scroll/VBox/ThisBuildingSection/DurabilityLabel
@onready var ports_label: Label = $Panel/Scroll/VBox/ThisBuildingSection/PortsLabel
@onready var info_extra_label: Label = $Panel/Scroll/VBox/ThisBuildingSection/InfoExtraLabel
@onready var instance_upgrade_label: Label = $Panel/Scroll/VBox/ThisBuildingSection/UpgradeRow/UpgradeLabel
@onready var instance_upgrade_button: Button = $Panel/Scroll/VBox/ThisBuildingSection/UpgradeRow/UpgradeButton
@onready var perk_label: Label = $Panel/Scroll/VBox/ThisBuildingSection/PerkLabel

@onready var global_upgrades_section: VBoxContainer = $Panel/Scroll/VBox/GlobalUpgradesSection
@onready var upgrade_rows_container: VBoxContainer = $Panel/Scroll/VBox/GlobalUpgradesSection/UpgradeRows
@onready var hire_section: VBoxContainer = $Panel/Scroll/VBox/HireSection
@onready var hire_rows_container: VBoxContainer = $Panel/Scroll/VBox/HireSection/HireRows

@onready var close_button: Button = $CloseButton
@onready var backdrop: ColorRect = $Backdrop

var _current_building: Node = null

var _upgrade_labels: Dictionary = {}
var _upgrade_buttons: Dictionary = {}
var _hire_buttons: Dictionary = {}
## Each blob kind's whole row (label + button), tracked separately from
## _hire_buttons so a not-yet-unlocked kind's row can be hidden entirely --
## see feature backlog: "New blob kinds unlock over time; hidden in UI
## until unlocked." Unlocking itself happens in TechTreePanel, not here.
var _hire_rows: Dictionary = {}


## Godot lifecycle hook: starts hidden, builds every rows section from its
## data source, and subscribes to GameManager so levels/costs/affordability/
## unlock-state stay current without any polling.
func _ready() -> void:
	visible = false
	_build_upgrade_rows()
	_build_hire_rows()
	instance_upgrade_button.pressed.connect(_on_instance_upgrade_pressed)
	close_button.pressed.connect(close_menu)
	backdrop.gui_input.connect(_on_backdrop_gui_input)
	GameManager.resource_changed.connect(func(_type, _total): _refresh())
	GameManager.upgrade_changed.connect(func(_stat, _level): _refresh())
	GameManager.blob_kind_unlocked.connect(func(_id): _refresh())

## Godot per-frame hook: factory pieces (belt/extractor/processor) have
## live status (carrying/buffered/linked) that changes every frame rather
## than only on a GameManager signal, so this section alone is kept fresh
## continuously while the menu is open instead of via signal-driven _refresh.
func _process(_delta: float) -> void:
	if visible and _current_building and is_instance_valid(_current_building) and _current_building.has_method("get_info_text"):
		info_extra_label.text = _current_building.get_info_text()

## Clicking the dimmed backdrop (i.e. outside the panel itself, since the
## panel sits on top of and consumes clicks before they reach here) closes
## the menu, same as the X button.
func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_menu()

## Opens the menu for `building` (called by World when a building is
## clicked), showing the Town-Hall-only sections only if this instance
## actually has that capability.
func open_menu(building: Node) -> void:
	_current_building = building
	var under_construction: bool = "is_under_construction" in building and building.is_under_construction
	var is_town_hall_like: bool = building.has_method("hire_blob") and not under_construction
	global_upgrades_section.visible = is_town_hall_like
	hire_section.visible = is_town_hall_like
	visible = true
	_refresh()

## Closes the menu, e.g. via its Close button.
func close_menu() -> void:
	visible = false
	_current_building = null

## Creates one row (label + button) per stat in GameManager.UPGRADE_STATS.
func _build_upgrade_rows() -> void:
	for stat in GameManager.UPGRADE_STATS:
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var button := Button.new()
		button.pressed.connect(func(): GameManager.try_purchase_upgrade(stat))

		var row := HBoxContainer.new()
		row.add_child(label)
		row.add_child(button)
		upgrade_rows_container.add_child(row)

		_upgrade_labels[stat] = label
		_upgrade_buttons[stat] = button

## Creates one row (label + button) per archetype in BlobKinds.
func _build_hire_rows() -> void:
	for kind_id in BlobKinds.get_ordered_ids():
		var kind = BlobKinds.get_kind(kind_id)

		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s\n%s" % [kind.display_name, kind.stat_summary()]

		var button := Button.new()
		button.pressed.connect(func(): _hire(kind_id))

		var row := HBoxContainer.new()
		row.add_child(label)
		row.add_child(button)
		hire_rows_container.add_child(row)

		_hire_buttons[kind_id] = button
		_hire_rows[kind_id] = row

## Button handler for a hire row: asks the currently-open building to spend
## wood and spawn the given kind. The building (not this menu) owns spawn
## logic; this section is only visible when that building supports it.
func _hire(kind_id: String) -> void:
	if _current_building and _current_building.has_method("hire_blob"):
		_current_building.hire_blob(kind_id)

## Button handler for the "This Building" upgrade button: asks the
## currently-open building instance to spend its next level's cost.
func _on_instance_upgrade_pressed() -> void:
	if _current_building and _current_building.has_method("try_upgrade"):
		_current_building.try_upgrade()
		_refresh()

## Refreshes the "This Building" section for whichever instance is
## currently open, every Global Upgrade row (level/cost/affordability), and
## every Hire row's button (cost/affordability).
func _refresh() -> void:
	_refresh_this_building()

	for stat in GameManager.UPGRADE_STATS:
		var level := GameManager.get_upgrade_level(stat)
		var cost := GameManager.get_upgrade_cost(stat)
		var display_name: String = GameManager.UPGRADE_DISPLAY_NAMES.get(stat, stat.capitalize())
		_upgrade_labels[stat].text = "%s Lv.%d" % [display_name, level]
		_upgrade_buttons[stat].text = "Upgrade (%d wood)" % cost
		_upgrade_buttons[stat].disabled = not GameManager.can_afford_upgrade(stat)

	for kind_id in BlobKinds.get_ordered_ids():
		var unlocked: bool = GameManager.is_blob_kind_unlocked(kind_id)
		_hire_rows[kind_id].visible = unlocked
		if not unlocked:
			continue
		var kind = BlobKinds.get_kind(kind_id)
		_hire_buttons[kind_id].text = "Hire (%d wood)" % kind.hire_cost
		_hire_buttons[kind_id].disabled = not GameManager.can_afford_cost(kind.hire_cost)

	_fit_to_content()

## Recomputes the panel's size from its current content (rather than the
## fixed box the .tscn used to hardcode) and re-centers it, so a
## content-light building (e.g. a Wall) gets a small box and a
## content-heavy one (Town Hall, with every section visible) gets a bigger
## one -- capped at MAX_PANEL_SIZE_FRACTION of the viewport either way, with
## the existing ScrollContainer taking over for whatever doesn't fit. The
## actual clamp math is shared with UnitInfoPanel via PanelAutofit (see
## scripts/core/panel_autofit.gd); only the natural-size computation and
## the final centered `position` below are specific to this panel.
const MIN_PANEL_SIZE := Vector2(280.0, 160.0)
const MAX_PANEL_SIZE_FRACTION := Vector2(0.85, 0.85)
## StyleBoxFlat_panel's own content margins (see theme/game_theme.tres) --
## get_combined_minimum_size() on `vbox` doesn't include the *ancestor*
## Panel's stylebox padding, so it's added back in here.
const PANEL_PADDING := Vector2(30.0, 24.0)
func _fit_to_content() -> void:
	var natural: Vector2 = vbox.get_combined_minimum_size() + PANEL_PADDING
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var target := PanelAutofit.resolve_size(natural, MIN_PANEL_SIZE, MAX_PANEL_SIZE_FRACTION, viewport_size)
	panel.custom_minimum_size = target
	panel.size = target
	panel.position = (viewport_size - target) * 0.5

## Populates name/durability/ports/upgrade-level/perk for whichever building
## is currently open. Every field is read via duck-typing ("x" in building)
## rather than assuming every building kind has every field -- Wall, for
## instance, has durability but no per-instance upgrade_level.
func _refresh_this_building() -> void:
	if _current_building == null or not is_instance_valid(_current_building):
		return
	var building := _current_building
	var kind_id: String = building.kind_id if "kind_id" in building else ""
	var building_kind = BuildingKinds.get_kind(kind_id) if kind_id != "" else null
	var display_name: String = building_kind.display_name if building_kind else building.get("display_name")
	if display_name == null:
		display_name = kind_id.capitalize() if kind_id != "" else "Building"

	name_label.text = display_name

	var under_construction: bool = "is_under_construction" in building and building.is_under_construction
	if under_construction:
		var required: float = building_kind.build_labor if building_kind else 1.0
		var pct: int = int(round(clamp(building.construction_progress / max(required, 0.001), 0.0, 1.0) * 100.0))
		construction_label.text = "Under Construction: %d%%\nSend blobs here (right-click while selected) to help build it." % pct
		construction_label.visible = true
	else:
		construction_label.visible = false

	# Every other section is meaningless (and hidden) while still under
	# construction -- there's nothing to upgrade/deliver to/hire from yet.
	if "durability" in building and "max_durability" in building and not under_construction:
		durability_label.text = "Durability: %d / %d" % [building.durability, building.max_durability]
		durability_label.visible = true
	else:
		durability_label.visible = false

	if building_kind and not under_construction:
		var input_desc: String = "none" if building_kind.input_ports.is_empty() else str(building_kind.input_ports.size())
		var output_desc: String = "none" if building_kind.output_ports.is_empty() else str(building_kind.output_ports.size())
		ports_label.text = "Inputs: %s   Outputs: %s" % [input_desc, output_desc]
		ports_label.visible = true
	else:
		ports_label.visible = false

	if building.has_method("get_info_text") and not under_construction:
		info_extra_label.text = building.get_info_text()
		info_extra_label.visible = true
	else:
		info_extra_label.visible = false

	var has_instance_upgrades: bool = "upgrade_level" in building and building_kind and not building_kind.upgrade_costs.is_empty() and not under_construction
	this_building_section.get_node("UpgradeRow").visible = has_instance_upgrades
	perk_label.visible = has_instance_upgrades
	if has_instance_upgrades:
		var level: int = building.upgrade_level
		var max_level: int = building_kind.upgrade_costs.size()
		instance_upgrade_label.text = "Upgrade Lv.%d/%d" % [level, max_level]
		if level < max_level:
			var cost: int = building_kind.upgrade_costs[level]
			instance_upgrade_button.text = "Upgrade (%d knowledge)" % cost
			instance_upgrade_button.disabled = not GameManager.can_afford("knowledge", cost)
			perk_label.text = "Next perk: %s" % building_kind.upgrade_perks[level]
		else:
			instance_upgrade_button.text = "Max Level"
			instance_upgrade_button.disabled = true
			perk_label.text = "Fully upgraded"
