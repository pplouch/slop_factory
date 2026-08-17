class_name BuildableStructure
extends StaticBody3D
## Base class (Template Method pattern) for every BuildingKinds-registered
## structure -- Building (Town Hall), StorageDepot, WaterTank. These used to
## each hand-roll an identical `is_under_construction`/`construction_progress`
## pair, an identical `add_construction_progress()` body, and a near-
## identical `try_upgrade()`; this holds the shared part. What's genuinely
## per-building (which meshes visually rise during construction, what
## happens on a successful upgrade, what a delivered item actually does) stays
## in the subclass via the `_construction_meshes()` hook and a `try_upgrade()`
## override that calls `super.try_upgrade()`.
##
## Deliberately does NOT include group registration (`add_to_group`) or a
## `_ready()` override -- subclasses call `_setup_durability()` themselves
## from their own `_ready()`, alongside whatever group memberships/timers/
## buffers they need, since those genuinely differ per building (e.g.
## Building doesn't join "structures", only "buildings" -- see CLAUDE.md).
##
## Not a base for Wall/BeltSegment/Extractor/Processor -- those are always-
## available factory pieces with no tech-tree gating and no construction
## delay, a different enough concept that forcing them under this class
## would just mean overriding most of it away.

## Which BuildingKinds entry this instance is -- set by World at placement
## time, before this node enters the tree. Used to look up display name,
## durability, upgrade costs/perks, and construction labor requirement.
@export var kind_id: String = ""

## Per-instance upgrade progress (0..BuildingKinds.get_kind(kind_id).upgrade_costs.size()),
## bought via BuildingMenu's "This Building" section -- distinct from
## GameManager's account-wide upgrades (speed/strength/...), which apply to
## every blob regardless of which building is open.
var upgrade_level := 0
var durability: int
var max_durability: int

## Whether this instance is still being built (see add_construction_progress)
## -- true for every freshly-placed building, since these are only ever
## created via Build Mode, never present at game start. Subclasses gate
## their own functionality (spawning/hiring/upgrading/accepting deliveries)
## on this being false.
var is_under_construction := true
var construction_progress := 0.0

# -- Under-construction progress bar (see _build_construction_bar) --
const CONSTRUCTION_BAR_WIDTH := 0.8
const CONSTRUCTION_BAR_HEIGHT := 0.12
const CONSTRUCTION_BAR_Y := 1.7
const CONSTRUCTION_BAR_COLOR := Color(1.0, 0.85, 0.3, 1.0)

## Null while finished/not yet built -- see _refresh_construction_bar.
var _construction_bar_root: Node3D = null
var _construction_bar_fill: MeshInstance3D = null
var _construction_bar_fill_mesh: QuadMesh = null


## Reads max_durability/durability from this instance's BuildingKinds entry.
## Called by each subclass's own _ready(), not automatically -- see header.
func _setup_durability() -> void:
	var kind := BuildingKinds.get_kind(kind_id)
	max_durability = kind.max_durability
	durability = max_durability

## Called by whichever blob(s) are in ConstructState with this building as
## their pending_build_target, once per physics frame. Finishes
## construction once BuildingKinds' build_labor is reached.
func add_construction_progress(amount: float) -> void:
	if not is_under_construction:
		return
	construction_progress += amount
	var required: float = BuildingKinds.get_kind(kind_id).build_labor
	if construction_progress >= required:
		is_under_construction = false
		_apply_construction_visual(1.0)
		Effects.spawn_command_marker(get_parent(), global_position + Vector3(0.0, 0.05, 0.0), Color(1.0, 0.85, 0.3, 1.0))
	else:
		_apply_construction_visual(construction_progress / required)

## Template Method hook: subclasses return the mesh(es) that should
## visually rise during construction, e.g.
## `[{"mesh": _body_mesh, "base_position": _body_base_position}]`. An entry
## may set `"scales": false` for a mesh that should only reposition as it
## rises, not also scale (Building's Roof sits on top of its Walls and
## never changes size, only height). Must include EVERY visible
## MeshInstance3D, not just the "main" body -- a decorative mesh left out
## (e.g. a port marker) renders at full size from the moment the structure
## is placed, misleadingly suggesting it's already built (see StorageDepot/
## WaterTank's port markers for the pattern to follow).
func _construction_meshes() -> Array:
	return []

## Scales/repositions every mesh `_construction_meshes()` returns so an
## in-progress structure visibly rises from a low foundation up to its full
## height -- never this StaticBody3D's own collider, which stays full-size
## throughout so the structure already occupies/blocks its cell the moment
## it's placed. A mesh's own position.y is repositioned proportionally
## (not just scaled) so its base stays anchored to the ground instead of
## shrinking toward its own midpoint and sinking half underground.
func _apply_construction_visual(fraction: float) -> void:
	var height_fraction: float = lerp(0.15, 1.0, clamp(fraction, 0.0, 1.0))
	for entry in _construction_meshes():
		var mesh: MeshInstance3D = entry["mesh"]
		var base_position: Vector3 = entry["base_position"]
		if entry.get("scales", true):
			mesh.scale.y = height_fraction
		mesh.position.y = base_position.y * height_fraction
	_refresh_construction_bar(fraction)

## Keeps the always-visible "still under construction" progress bar in sync
## with `fraction`, building it lazily the first time this runs rather than
## needing every subclass's own _ready() to call one more setup method --
## every subclass already calls _apply_construction_visual(0.0) there (see
## that method's own header), so this piggybacks on the exact same call
## sites (_ready(), every add_construction_progress() tick, and the
## finishing call) rather than needing a new one. Torn down for good once
## construction actually finishes (fraction >= 1.0), since a finished
## building has nothing left to indicate (see feature backlog: "building
## should have a visual tip that it's not finished yet" -- previously the
## only cue was the rise-from-ground mesh animation itself, easy to miss
## once a building is most of the way up, or opening BuildingMenu to read
## its progress as text).
func _refresh_construction_bar(fraction: float) -> void:
	if fraction >= 1.0:
		if _construction_bar_root:
			_construction_bar_root.queue_free()
			_construction_bar_root = null
			_construction_bar_fill = null
			_construction_bar_fill_mesh = null
		return
	if _construction_bar_root == null:
		_build_construction_bar()
	# Directly resizes the fill QuadMesh's own geometry and repositions its
	# instance to keep the left edge pinned to the bg's left edge as the
	# right edge grows -- rather than the more common "scale a pivoted
	# child" bar trick (still fine for Combatant's own health bar, which
	# only shrinks). A billboarded quad under a *non-uniformly* scaled
	# parent (scale.x changing, y/z fixed at 1) doesn't grow in place the
	# way a flat 2D UI bar would -- it visibly reads as the gold fill
	# sliding in from one side rather than filling, since the billboard
	# reconstructs the quad's facing every frame from a transform whose
	# scale was never uniform to begin with (see feature backlog: "the bar
	# doesn't fill with gold but a gold bar translates slowly into the
	# empty bar"). Resizing the mesh resource itself sidesteps that
	# entirely -- there's no parent scale involved at all.
	var fill_width: float = CONSTRUCTION_BAR_WIDTH * clamp(fraction, 0.0, 1.0)
	_construction_bar_fill_mesh.size = Vector2(max(fill_width, 0.001), CONSTRUCTION_BAR_HEIGHT)
	_construction_bar_fill.position.x = -CONSTRUCTION_BAR_WIDTH * 0.5 + fill_width * 0.5

## Builds a two-quad billboarded progress bar (dark background + gold fill),
## the same construction Combatant._build_health_bar uses for a unit's
## health bar -- see that method's own comments for why each quad material
## needs billboard_mode + cull_mode disabled + no_depth_test + a staggered
## render_priority. Floats above the structure (rather than at its feet like
## a health bar) so it stays visible over the mesh that's still rising
## toward it (see _apply_construction_visual) instead of the two overlapping.
## Unlike Combatant's own bar, the fill quad isn't parented under a scaled
## pivot -- see _refresh_construction_bar's own comment for why this bar
## resizes the QuadMesh resource directly instead.
func _build_construction_bar() -> void:
	_construction_bar_root = Node3D.new()
	_construction_bar_root.position = Vector3(0.0, CONSTRUCTION_BAR_Y, 0.0)
	add_child(_construction_bar_root)

	var bg := MeshInstance3D.new()
	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(CONSTRUCTION_BAR_WIDTH, CONSTRUCTION_BAR_HEIGHT)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 1
	bg_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.85)
	bg_mesh.material = bg_mat
	bg.mesh = bg_mesh
	_construction_bar_root.add_child(bg)

	_construction_bar_fill_mesh = QuadMesh.new()
	_construction_bar_fill_mesh.size = Vector2(0.001, CONSTRUCTION_BAR_HEIGHT)
	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fill_mat.no_depth_test = true
	fill_mat.render_priority = 2
	fill_mat.albedo_color = CONSTRUCTION_BAR_COLOR
	_construction_bar_fill_mesh.material = fill_mat

	_construction_bar_fill = MeshInstance3D.new()
	_construction_bar_fill.mesh = _construction_bar_fill_mesh
	_construction_bar_fill.position = Vector3(-CONSTRUCTION_BAR_WIDTH * 0.5, 0.0, 0.002)
	_construction_bar_root.add_child(_construction_bar_fill)

## Attempts to spend this instance's next upgrade level's knowledge cost
## (see BuildingKinds.upgrade_costs) -- knowledge, not wood, since a
## per-building "perk" tier is the same kind of spend as the tech tree's
## building-unlock tiers (see GameManager.try_unlock_building), both
## sourced from ResearchCenter rather than ordinary gathering. Returns
## whether it went through. Subclasses with an extra effect on a successful
## purchase (Building's spawn-timer speedup) override this and call
## `super.try_upgrade()` first.
func try_upgrade() -> bool:
	if is_under_construction:
		return false
	var kind := BuildingKinds.get_kind(kind_id)
	if upgrade_level >= kind.upgrade_costs.size():
		return false
	if not GameManager.try_spend("knowledge", kind.upgrade_costs[upgrade_level]):
		return false
	upgrade_level += 1
	return true
