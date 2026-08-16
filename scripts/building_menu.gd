extends CanvasLayer
## The generic modal opened by left-clicking any building (Town Hall,
## Storage Depot, Wall, ...). Every building gets the "This Building"
## section (name/durability/per-instance upgrade+perk/inputs/outputs, read
## from whichever instance was clicked); the account-wide Global Upgrades,
## Hire, and Unlock Buildings sections only show for buildings that expose
## Town-Hall-specific capabilities (duck-typed via has_method("hire_blob")),
## since those concepts (spending on a global stat, hiring a blob) don't
## make sense for e.g. a Storage Depot or a Wall.
##
## Every section is built entirely from data rather than hardcoded scene
## nodes: the upgrade rows come from GameManager.UPGRADE_STATS, the hire
## rows come from BlobKinds' registered archetypes, the unlock rows come
## from BuildingKinds. Adding a new stat/blob kind/building kind therefore
## needs no changes here or in the .tscn.
##
## Refreshes reactively whenever GameManager's resource/upgrade/unlock
## signals fire, rather than polling every frame.

@onready var this_building_section: VBoxContainer = $Panel/Scroll/VBox/ThisBuildingSection
@onready var name_label: Label = $Panel/Scroll/VBox/ThisBuildingSection/NameLabel
@onready var durability_label: Label = $Panel/Scroll/VBox/ThisBuildingSection/DurabilityLabel
@onready var ports_label: Label = $Panel/Scroll/VBox/ThisBuildingSection/PortsLabel
@onready var instance_upgrade_label: Label = $Panel/Scroll/VBox/ThisBuildingSection/UpgradeRow/UpgradeLabel
@onready var instance_upgrade_button: Button = $Panel/Scroll/VBox/ThisBuildingSection/UpgradeRow/UpgradeButton
@onready var perk_label: Label = $Panel/Scroll/VBox/ThisBuildingSection/PerkLabel

@onready var global_upgrades_section: VBoxContainer = $Panel/Scroll/VBox/GlobalUpgradesSection
@onready var upgrade_rows_container: VBoxContainer = $Panel/Scroll/VBox/GlobalUpgradesSection/UpgradeRows
@onready var hire_section: VBoxContainer = $Panel/Scroll/VBox/HireSection
@onready var hire_rows_container: VBoxContainer = $Panel/Scroll/VBox/HireSection/HireRows
@onready var unlock_section: VBoxContainer = $Panel/Scroll/VBox/UnlockSection
@onready var unlock_rows_container: VBoxContainer = $Panel/Scroll/VBox/UnlockSection/UnlockRows

@onready var close_button: Button = $CloseButton
@onready var backdrop: ColorRect = $Backdrop

var _current_building: Node = null

var _upgrade_labels: Dictionary = {}
var _upgrade_buttons: Dictionary = {}
var _hire_buttons: Dictionary = {}
var _unlock_labels: Dictionary = {}
var _unlock_buttons: Dictionary = {}
var _unlock_rows: Dictionary = {}


## Godot lifecycle hook: starts hidden, builds every rows section from its
## data source, and subscribes to GameManager so levels/costs/affordability/
## unlock-state stay current without any polling.
func _ready() -> void:
	visible = false
	_build_upgrade_rows()
	_build_hire_rows()
	_build_unlock_rows()
	instance_upgrade_button.pressed.connect(_on_instance_upgrade_pressed)
	close_button.pressed.connect(close_menu)
	backdrop.gui_input.connect(_on_backdrop_gui_input)
	GameManager.resource_changed.connect(func(_type, _total): _refresh())
	GameManager.upgrade_changed.connect(func(_stat, _level): _refresh())
	GameManager.building_unlocked.connect(func(_id): _refresh())

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
	var is_town_hall_like: bool = building.has_method("hire_blob")
	global_upgrades_section.visible = is_town_hall_like
	hire_section.visible = is_town_hall_like
	unlock_section.visible = is_town_hall_like
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

## Button handler for a hire row: asks the currently-open building to spend
## wood and spawn the given kind. The building (not this menu) owns spawn
## logic; this section is only visible when that building supports it.
func _hire(kind_id: String) -> void:
	if _current_building and _current_building.has_method("hire_blob"):
		_current_building.hire_blob(kind_id)

## Creates one row (label + button) per BuildingKinds entry that actually
## needs unlocking (unlock_cost > 0 -- Town Hall is always-unlocked and has
## no row at all, since there's nothing to buy). A row hides itself once
## its building is unlocked (see _refresh) rather than being removed, so
## rebuilding rows from scratch is never needed.
func _build_unlock_rows() -> void:
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
		unlock_rows_container.add_child(row)

		_unlock_labels[building_id] = label
		_unlock_buttons[building_id] = button
		_unlock_rows[building_id] = row

## Button handler for the "This Building" upgrade button: asks the
## currently-open building instance to spend its next level's cost.
func _on_instance_upgrade_pressed() -> void:
	if _current_building and _current_building.has_method("try_upgrade"):
		_current_building.try_upgrade()
		_refresh()

## Refreshes the "This Building" section for whichever instance is
## currently open, every Global Upgrade row (level/cost/affordability),
## every Hire row's button (cost/affordability), and every Unlock row.
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
		var kind = BlobKinds.get_kind(kind_id)
		_hire_buttons[kind_id].text = "Hire (%d wood)" % kind.hire_cost
		_hire_buttons[kind_id].disabled = not GameManager.can_afford_cost(kind.hire_cost)

	for building_id in _unlock_rows.keys():
		var unlocked: bool = GameManager.is_building_unlocked(building_id)
		_unlock_rows[building_id].visible = not unlocked
		if unlocked:
			continue
		var kind = BuildingKinds.get_kind(building_id)
		var prereq_ok: bool = kind.requires == "" or GameManager.is_building_unlocked(kind.requires)
		var label_text: String = kind.display_name
		if not prereq_ok:
			label_text += " (needs %s)" % BuildingKinds.get_kind(kind.requires).display_name
		_unlock_labels[building_id].text = label_text
		_unlock_buttons[building_id].text = "Unlock (%d wood)" % kind.unlock_cost
		_unlock_buttons[building_id].disabled = not GameManager.can_unlock_building(building_id)

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

	if "durability" in building and "max_durability" in building:
		durability_label.text = "Durability: %d / %d" % [building.durability, building.max_durability]
		durability_label.visible = true
	else:
		durability_label.visible = false

	if building_kind:
		var input_desc: String = "none" if building_kind.input_ports.is_empty() else str(building_kind.input_ports.size())
		var output_desc: String = "none" if building_kind.output_ports.is_empty() else str(building_kind.output_ports.size())
		ports_label.text = "Inputs: %s   Outputs: %s" % [input_desc, output_desc]
		ports_label.visible = true
	else:
		ports_label.visible = false

	var has_instance_upgrades: bool = "upgrade_level" in building and building_kind and not building_kind.upgrade_costs.is_empty()
	this_building_section.get_node("UpgradeRow").visible = has_instance_upgrades
	perk_label.visible = has_instance_upgrades
	if has_instance_upgrades:
		var level: int = building.upgrade_level
		var max_level: int = building_kind.upgrade_costs.size()
		instance_upgrade_label.text = "Upgrade Lv.%d/%d" % [level, max_level]
		if level < max_level:
			var cost: int = building_kind.upgrade_costs[level]
			instance_upgrade_button.text = "Upgrade (%d wood)" % cost
			instance_upgrade_button.disabled = not GameManager.can_afford_cost(cost)
			perk_label.text = "Next perk: %s" % building_kind.upgrade_perks[level]
		else:
			instance_upgrade_button.text = "Max Level"
			instance_upgrade_button.disabled = true
			perk_label.text = "Fully upgraded"
