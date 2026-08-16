extends CanvasLayer
## Bottom-left panel showing info about the current blob selection.
##
## A single selected blob gets the detailed view (kind/task/stats/
## inventory) -- see show_blob. Multiple selected blobs get a compact
## overview instead (see show_group): one row per BlobKinds kind present in
## the selection, each blob in that kind shown as a small rectangle whose
## fill width/color reflects its current health fraction, so a glance tells
## you both squad composition and how banged-up it is.
##
## Chip Control nodes are only rebuilt when the tracked group's *membership*
## changes (a blob was added, removed, or died) -- every other frame just
## rescales the existing chips' fill rects from live health values, so a
## panel that's visible continuously doesn't churn nodes every frame.

const CHIP_SIZE := Vector2(16, 10)
const CHIP_GAP := 3.0
const HEALTHY_COLOR := Color(0.3, 0.9, 0.35)
const HURT_COLOR := Color(0.9, 0.2, 0.2)

@onready var panel: PanelContainer = $Panel
@onready var single_view: VBoxContainer = $Panel/Scroll/VBox
@onready var name_label: Label = $Panel/Scroll/VBox/NameLabel
@onready var task_label: Label = $Panel/Scroll/VBox/TaskLabel
@onready var stats_label: Label = $Panel/Scroll/VBox/StatsLabel
@onready var inventory_label: Label = $Panel/Scroll/VBox/InventoryLabel
@onready var group_view: VBoxContainer = $Panel/Scroll/GroupVBox

var _tracked_blob: Node = null
var _tracked_group: Array = []
## blob instance -> its chip's foreground (health-fill) ColorRect, so a
## per-frame health refresh can restyle existing chips without rebuilding.
var _group_chips: Dictionary = {}


## Godot lifecycle hook: starts hidden.
func _ready() -> void:
	panel.visible = false

## Starts displaying (and continuously refreshing) a single blob's detailed
## info. Switches away from group mode if that was active.
func show_blob(blob: Node) -> void:
	_tracked_blob = blob
	_tracked_group = []
	panel.visible = true
	single_view.visible = true
	group_view.visible = false
	_refresh()

## Starts displaying the compact grouped overview for multiple selected
## blobs. Switches away from single mode if that was active.
func show_group(blobs: Array) -> void:
	_tracked_blob = null
	_tracked_group = blobs.duplicate()
	panel.visible = true
	single_view.visible = false
	group_view.visible = true
	_rebuild_group_view()

## Hides the panel and stops tracking whatever it was showing.
func hide_panel() -> void:
	_tracked_blob = null
	_tracked_group = []
	panel.visible = false

## Godot per-frame hook: keeps whichever view is active live, auto-hiding
## (single mode) or auto-rebuilding (group mode, only when membership
## actually changed) if tracked blobs have died since the last frame.
func _process(_delta: float) -> void:
	if not panel.visible:
		return
	if group_view.visible:
		var pruned: Array = _tracked_group.filter(is_instance_valid)
		if pruned.size() != _tracked_group.size():
			_tracked_group = pruned
			if _tracked_group.is_empty():
				hide_panel()
				return
			_rebuild_group_view()
		_refresh_group_health()
		return
	if not is_instance_valid(_tracked_blob):
		hide_panel()
		return
	_refresh()

## Repopulates every single-view label from the tracked blob's current fields.
func _refresh() -> void:
	var blob = _tracked_blob
	var kind = BlobKinds.get_kind(blob.kind_id)

	name_label.text = kind.display_name
	task_label.text = "Task: %s" % blob.current_state.display_name(blob)
	stats_label.text = "HP %d/%d   Spd %.1f   Atk %.1f   Dex %.1f" % [
		ceili(blob.health), int(blob.max_health), blob.speed, blob.attack_power, blob.dexterity
	]

	var total := 0
	var parts: Array = []
	for resource_type in blob.inventory.keys():
		var amount: int = blob.inventory[resource_type]
		total += amount
		parts.append("%s %d" % [String(resource_type).capitalize(), amount])
	var carrying := ", ".join(parts) if not parts.is_empty() else "nothing"
	inventory_label.text = "Carrying: %s (%d/%d)" % [carrying, total, blob.carry_capacity]

## Clears and rebuilds the grouped view from scratch: one header + one
## health-chip row per BlobKinds kind present in the current selection.
## Only called when the tracked group's membership changes, not every frame.
func _rebuild_group_view() -> void:
	for child in group_view.get_children():
		child.queue_free()
	_group_chips.clear()

	var groups: Dictionary = {}
	for blob in _tracked_group:
		if not groups.has(blob.kind_id):
			groups[blob.kind_id] = []
		groups[blob.kind_id].append(blob)

	for kind_id in groups.keys():
		var kind = BlobKinds.get_kind(kind_id)
		var blobs_of_kind: Array = groups[kind_id]

		var header := Label.new()
		header.add_theme_font_size_override("font_size", 13)
		header.text = "%s x%d" % [kind.display_name, blobs_of_kind.size()]
		group_view.add_child(header)

		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", int(CHIP_GAP))
		row.add_theme_constant_override("v_separation", int(CHIP_GAP))
		group_view.add_child(row)

		for blob in blobs_of_kind:
			row.add_child(_make_health_chip(blob))

	_refresh_group_health()

## Builds one health-chip Control (dark background + colored fill sized to
## the blob's current health fraction) for `blob`, and records its fill
## rect in _group_chips for cheap per-frame updates.
func _make_health_chip(blob: Node) -> Control:
	var chip := Control.new()
	chip.custom_minimum_size = CHIP_SIZE

	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.12, 0.9)
	bg.position = Vector2.ZERO
	bg.size = CHIP_SIZE
	chip.add_child(bg)

	var fill := ColorRect.new()
	fill.position = Vector2.ZERO
	fill.size = CHIP_SIZE
	chip.add_child(fill)

	_group_chips[blob] = fill
	return chip

## Rescales/recolors every existing chip's fill rect from its blob's live
## health fraction, without touching node structure.
func _refresh_group_health() -> void:
	for blob in _group_chips.keys():
		if not is_instance_valid(blob):
			continue
		var fill: ColorRect = _group_chips[blob]
		var fraction: float = clamp(blob.health / blob.max_health, 0.0, 1.0) if blob.max_health > 0.0 else 0.0
		fill.size = Vector2(CHIP_SIZE.x * fraction, CHIP_SIZE.y)
		fill.color = HEALTHY_COLOR.lerp(HURT_COLOR, 1.0 - fraction)
