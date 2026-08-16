extends CanvasLayer
## Bottom-left panel showing info about the current blob selection.
##
## Always renders as one colored box per BlobKinds kind present in the
## selection (background tinted to that kind's own body color, via
## BlobKinds.Kind.body_color) -- a single selected blob is just the size-1
## case of the same layout, so there's one code path instead of a separate
## "single blob detail" view and "group overview". Each box shows the
## kind's name/count, its stat summary, a short "special aptitude" blurb
## (BlobKinds.Kind.trait_description), and a small per-blob health chip
## row. When exactly one blob is tracked, its live current task and
## inventory are appended below that one box.
##
## A standing-orders row (Patrol/Hold/Explore buttons, mirroring the P/H/X
## keyboard shortcuts, plus a static "Move: Right-click" hint) is always
## shown beneath the boxes whenever anything is selected -- this is a dumb
## view like every other UI panel here: it only emits signals, World owns
## what pressing them actually does.
##
## Chip Control nodes (and the boxes themselves) are only rebuilt when the
## tracked group's *membership* changes (a blob was added, removed, or
## died) -- every other frame just refreshes live text/fill values on the
## existing nodes. The whole panel is resized to fit its current content
## every time it's rebuilt (see _fit_to_content), rather than being a fixed
## box regardless of how much or little there is to show.

signal patrol_requested
signal hold_requested
signal explore_requested

const CHIP_SIZE := Vector2(16, 10)
const CHIP_GAP := 3.0
const HEALTHY_COLOR := Color(0.3, 0.9, 0.35)
const HURT_COLOR := Color(0.9, 0.2, 0.2)

const MIN_PANEL_SIZE := Vector2(240.0, 90.0)
const MAX_PANEL_SIZE_FRACTION := Vector2(0.5, 0.6)
## StyleBoxFlat_panel's own content margins (see theme/game_theme.tres) --
## Control.get_combined_minimum_size() doesn't include an *ancestor*
## Panel's stylebox padding, so it's added back in here.
const PANEL_PADDING := Vector2(30.0, 24.0)
const PANEL_MARGIN := 16.0

@onready var panel: PanelContainer = $Panel
@onready var boxes_container: VBoxContainer = $Panel/OuterVBox/Scroll/BoxesVBox
@onready var orders_row: HBoxContainer = $Panel/OuterVBox/OrdersRow
@onready var orders_separator: HSeparator = $Panel/OuterVBox/OrdersSeparator
@onready var patrol_button: Button = $Panel/OuterVBox/OrdersRow/PatrolButton
@onready var hold_button: Button = $Panel/OuterVBox/OrdersRow/HoldButton
@onready var explore_button: Button = $Panel/OuterVBox/OrdersRow/ExploreButton

var _tracked_group: Array = []
## blob instance -> its chip's foreground (health-fill) ColorRect, so a
## per-frame health refresh can restyle existing chips without rebuilding.
var _group_chips: Dictionary = {}
## Only populated when exactly one blob is tracked (see _make_kind_box).
var _solo_task_label: Label = null
var _solo_inventory_label: Label = null


## Godot lifecycle hook: starts hidden and wires the standing-order buttons
## to their signals.
func _ready() -> void:
	panel.visible = false
	patrol_button.pressed.connect(func(): patrol_requested.emit())
	hold_button.pressed.connect(func(): hold_requested.emit())
	explore_button.pressed.connect(func(): explore_requested.emit())

## Starts displaying (and continuously refreshing) a single blob. Just the
## size-1 case of show_group -- kept as a separate entry point since World
## already distinguishes "one blob" from "multiple" when selection changes.
func show_blob(blob: Node) -> void:
	show_group([blob])

## Starts displaying the tracked group (one blob or many, same layout).
func show_group(blobs: Array) -> void:
	_tracked_group = blobs.duplicate()
	panel.visible = true
	_rebuild_view()

## Hides the panel and stops tracking whatever it was showing.
func hide_panel() -> void:
	_tracked_group = []
	panel.visible = false

## Godot per-frame hook: keeps the view live, auto-hiding or auto-rebuilding
## (only when membership actually changed) if tracked blobs have died since
## the last frame, otherwise just refreshing live fields on existing nodes.
func _process(_delta: float) -> void:
	if not panel.visible:
		return
	var pruned: Array = _tracked_group.filter(is_instance_valid)
	if pruned.size() != _tracked_group.size():
		_tracked_group = pruned
		if _tracked_group.is_empty():
			hide_panel()
			return
		_rebuild_view()
		return
	_refresh_live_fields()

## Clears and rebuilds one box per BlobKinds kind present in the current
## selection, then resizes the panel to match. Only called when the
## tracked group's membership changes, not every frame.
func _rebuild_view() -> void:
	# Immediate free(), not queue_free(): a rebuild that follows hot on the
	# heels of a previous one (e.g. selection changing twice in one frame)
	# must not find a stale box still counted as a child a moment later.
	for child in boxes_container.get_children():
		child.free()
	_group_chips.clear()
	_solo_task_label = null
	_solo_inventory_label = null

	var groups: Dictionary = {}
	for blob in _tracked_group:
		if not groups.has(blob.kind_id):
			groups[blob.kind_id] = []
		groups[blob.kind_id].append(blob)

	for kind_id in groups.keys():
		boxes_container.add_child(_make_kind_box(BlobKinds.get_kind(kind_id), groups[kind_id]))

	_refresh_live_fields()
	_fit_to_content()

## Builds one colored box for `kind`, containing its name+count, stat
## summary, special-aptitude blurb, and a health chip per blob of that
## kind. If this is the only kind box being built at all (i.e. exactly one
## blob total is selected), also appends live task/inventory labels,
## recording them so _refresh_live_fields can keep them current.
func _make_kind_box(kind, blobs_of_kind: Array) -> Control:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = kind.body_color().darkened(0.55)
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	box.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	box.add_child(vbox)

	var header := Label.new()
	header.add_theme_font_size_override("font_size", 15)
	header.text = "%s x%d" % [kind.display_name, blobs_of_kind.size()]
	vbox.add_child(header)

	var stats := Label.new()
	stats.add_theme_font_size_override("font_size", 12)
	stats.text = kind.stat_summary()
	vbox.add_child(stats)

	# No autowrap: a freshly-created Label has no established width yet when
	# _fit_to_content queries minimum size in this same frame, so wrapping
	# would estimate against a bogus near-zero width and wildly inflate the
	# computed minimum height. These blurbs are short enough to read as one
	# line; the panel's own width simply grows a little to fit instead.
	var trait_label := Label.new()
	trait_label.add_theme_font_size_override("font_size", 11)
	trait_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.8))
	trait_label.text = kind.trait_description
	vbox.add_child(trait_label)

	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", int(CHIP_GAP))
	row.add_theme_constant_override("v_separation", int(CHIP_GAP))
	vbox.add_child(row)
	for blob in blobs_of_kind:
		row.add_child(_make_health_chip(blob))

	if _tracked_group.size() == 1:
		_solo_task_label = Label.new()
		_solo_task_label.add_theme_font_size_override("font_size", 12)
		vbox.add_child(_solo_task_label)

		_solo_inventory_label = Label.new()
		_solo_inventory_label.add_theme_font_size_override("font_size", 12)
		vbox.add_child(_solo_inventory_label)

	return box

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
## health fraction, and (when solo) refreshes the live task/inventory
## labels -- all without touching node structure.
func _refresh_live_fields() -> void:
	for blob in _group_chips.keys():
		if not is_instance_valid(blob):
			continue
		var fill: ColorRect = _group_chips[blob]
		var fraction: float = clamp(blob.health / blob.max_health, 0.0, 1.0) if blob.max_health > 0.0 else 0.0
		fill.size = Vector2(CHIP_SIZE.x * fraction, CHIP_SIZE.y)
		fill.color = HEALTHY_COLOR.lerp(HURT_COLOR, 1.0 - fraction)

	if _tracked_group.size() != 1 or not is_instance_valid(_tracked_group[0]):
		return
	var blob = _tracked_group[0]
	if _solo_task_label:
		_solo_task_label.text = "Task: %s" % blob.current_state.display_name(blob)
	if _solo_inventory_label:
		var total := 0
		var parts: Array = []
		for resource_type in blob.inventory.keys():
			var amount: int = blob.inventory[resource_type]
			total += amount
			parts.append("%s %d" % [String(resource_type).capitalize(), amount])
		var carrying: String = ", ".join(parts) if not parts.is_empty() else "nothing"
		_solo_inventory_label.text = "Carrying: %s (%d/%d)" % [carrying, total, blob.carry_capacity]

## Recomputes the panel's size from its current content (rather than the
## fixed box the .tscn used to hardcode) and repositions it so its bottom-
## left corner stays pinned to the same screen margin regardless of size --
## capped at MAX_PANEL_SIZE_FRACTION of the viewport, with the existing
## ScrollContainer taking over for whatever doesn't fit (e.g. many kinds
## selected at once).
func _fit_to_content() -> void:
	var boxes_natural: Vector2 = boxes_container.get_combined_minimum_size()
	var orders_natural: Vector2 = orders_row.get_combined_minimum_size()
	var separator_height: float = orders_separator.get_combined_minimum_size().y
	var natural := Vector2(
		max(boxes_natural.x, orders_natural.x),
		boxes_natural.y + separator_height + orders_natural.y
	) + PANEL_PADDING

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var max_size := Vector2(viewport_size.x * MAX_PANEL_SIZE_FRACTION.x, viewport_size.y * MAX_PANEL_SIZE_FRACTION.y)
	var target := Vector2(
		clamp(natural.x, MIN_PANEL_SIZE.x, max_size.x),
		clamp(natural.y, MIN_PANEL_SIZE.y, max_size.y)
	)
	panel.custom_minimum_size = target
	panel.size = target
	panel.position = Vector2(PANEL_MARGIN, viewport_size.y - PANEL_MARGIN - target.y)
