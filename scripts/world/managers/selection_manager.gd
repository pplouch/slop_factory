class_name SelectionManager
extends RefCounted
## Mouse-driven unit selection (click, shift-click, drag-box) and hover
## highlighting -- split out of world.gd (see CLAUDE.md's "world.gd -- the
## central controller" section). OrderManager holds a reference to this
## manager: standing orders and right-click order issuing both act on
## whatever's currently selected, and right-click order issuing also reuses
## find_building_owner to tell "clicked a building" apart from "clicked bare
## ground/a resource node".

const MASK_BLOBS := 2
const MASK_RESOURCES := 4
const MASK_ENEMIES := 8

## Deliberately public (no leading underscore) -- OrderManager reads and
## (when pruning dead blobs before issuing a command) reassigns this
## directly, then calls selection_changed() itself afterward.
var selected_blobs: Array = []

var _world: Node3D
var _dragging := false
var _drag_start := Vector2.ZERO
var _hovered_blob: Node = null


func setup(world: Node3D) -> void:
	_world = world

## Handles a plain (non-drag) left click: selects a blob if one was clicked,
## opens a basic-info popup if an enemy was clicked, opens the generic
## building info modal if a building was clicked, opens the resource info
## modal if a resource node was clicked, or clears the selection if empty
## ground was clicked (unless shift/additive is held, in which case an
## empty click does nothing).
func handle_click_select(pos: Vector2, additive: bool) -> void:
	var hit: Dictionary = _world.raycast(pos, MASK_BLOBS)
	if hit and hit.collider.is_in_group("blobs"):
		if not additive:
			clear_selection()
		select_blob(hit.collider)
		selection_changed()
		return

	var enemy_hit: Dictionary = _world.raycast(pos, MASK_ENEMIES)
	if enemy_hit and enemy_hit.collider.is_in_group("enemies"):
		_world.enemy_info_panel.open_for(enemy_hit.collider)
		return

	var resource_hit: Dictionary = _world.raycast(pos, MASK_RESOURCES)
	if resource_hit:
		var building_owner := find_building_owner(resource_hit.collider)
		if building_owner:
			_world.building_menu.open_menu(building_owner)
			return
		if resource_hit.collider.is_in_group("resource_nodes"):
			_world.resource_info_panel.open_for(resource_hit.collider)
			return

	if not additive:
		clear_selection()
	selection_changed()

## A clicked collider is almost always the building itself directly -- every
## BuildableStructure (Building/StorageDepot/WaterTank, LinkableBuilding's
## Wall) attaches its script straight to a root StaticBody3D. The one
## remaining case where it's a nested body whose *parent* is the actual
## owner is BeltSegment's ClickArea (a non-physics Area3D child added purely
## so a belt, which stays a zero-footprint structure for blobs to walk over,
## can still be clicked) -- checks both, returning null if neither applies.
## Also matches "structures" (extractor/processor/belt), which open the same
## generic BuildingMenu even though they aren't part of the separate
## "buildings" group Blob._find_nearest_building searches for a deposit
## target -- a belt out in the field must never be mistaken for one.
func find_building_owner(collider: Node) -> Node:
	if collider.is_in_group("buildings") or collider.is_in_group("structures"):
		return collider
	var parent := collider.get_parent()
	if parent and (parent.is_in_group("buildings") or parent.is_in_group("structures")):
		return parent
	return null

## Handles a left-click drag: selects every blob whose on-screen projected
## position falls inside the dragged rectangle (skipping any blob currently
## behind the camera, which would otherwise project to a bogus screen point).
func handle_box_select(a: Vector2, b: Vector2, additive: bool) -> void:
	if not additive:
		clear_selection()
	var rect := Rect2(a, Vector2.ZERO).expand(b)
	for blob in _world.get_tree().get_nodes_in_group("blobs"):
		var to_blob: Vector3 = blob.global_position - _world.camera.global_position
		if _world.camera.global_transform.basis.z.dot(to_blob) > 0.0:
			continue
		var screen_pos: Vector2 = _world.camera.unproject_position(blob.global_position)
		if rect.has_point(screen_pos):
			select_blob(blob)
	selection_changed()

## Updates which blob (if any) is under the mouse cursor and toggles its
## hover highlight, clearing the previous hover target first. Only called
## while the player isn't drag-selecting.
func update_hover(pos: Vector2) -> void:
	var hit: Dictionary = _world.raycast(pos, MASK_BLOBS)
	var hovered = hit.collider if hit and hit.collider.is_in_group("blobs") else null
	if hovered == _hovered_blob:
		return
	if is_instance_valid(_hovered_blob):
		_hovered_blob.set_hovered(false)
	_hovered_blob = hovered
	if is_instance_valid(_hovered_blob):
		_hovered_blob.set_hovered(true)

## Adds `blob` to the current selection (no-op if already selected) and
## turns on its selection ring.
func select_blob(blob: Node) -> void:
	if selected_blobs.has(blob):
		return
	selected_blobs.append(blob)
	blob.set_selected(true)

## Deselects every currently-selected blob and empties the selection.
func clear_selection() -> void:
	for blob in selected_blobs:
		if is_instance_valid(blob):
			blob.set_selected(false)
	selected_blobs.clear()

## Called after anything that adds/removes/prunes the selection: updates the
## HUD's count and shows/hides the unit-info panel to match. A single
## selected blob gets the detailed stats/inventory view; multiple get a
## compact per-kind grouped overview instead of hiding the panel entirely.
func selection_changed() -> void:
	_world.hud.set_selected_count(selected_blobs.size())
	if selected_blobs.is_empty():
		_world.unit_info_panel.hide_panel()
	elif selected_blobs.size() == 1 and is_instance_valid(selected_blobs[0]):
		_world.unit_info_panel.show_blob(selected_blobs[0])
	else:
		_world.unit_info_panel.show_group(selected_blobs)

## Handles the left-mouse-button input event lifecycle (drag-start on press,
## click-vs-box-select resolution on release) -- called by World's
## _unhandled_input for InputEventMouseButton events on MOUSE_BUTTON_LEFT.
func handle_left_button(event: InputEventMouseButton) -> void:
	if event.pressed:
		_dragging = true
		_drag_start = event.position
	else:
		if _dragging:
			if _drag_start.distance_to(event.position) < 6.0:
				handle_click_select(event.position, event.shift_pressed)
			else:
				handle_box_select(_drag_start, event.position, event.shift_pressed)
		_dragging = false
		_world.selection_box.hide_rect()

## Handles mouse-motion input while not in build mode: updates the drag-box
## visual while dragging, otherwise drives the hover highlight.
func handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _dragging:
		_world.selection_box.show_rect(_drag_start, event.position)
	else:
		update_hover(event.position)
