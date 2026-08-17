extends BuildableStructure
## The tech tree's knowledge source -- unlike the other 4 new-building stubs
## (see scripts/buildings/simple_building.gd), this one graduated to real
## behavior once the Tech Tree panel needed "knowledge" to actually come
## from somewhere: a periodic trickle, mirroring Building's free-blob-spawn
## timer but simpler (no hire interaction, no global "growth" upgrade tie-in
## -- just this instance's own upgrade_level).
##
## `kind_id`, `upgrade_level`, `durability`/`max_durability`,
## `is_under_construction`/`construction_progress`, `add_construction_progress()`
## all come from BuildableStructure (see scripts/core/buildable_structure.gd).

const BASE_KNOWLEDGE_PER_TICK := 5
## Each upgrade level (see BuildingKinds.get_kind("research_center")) adds
## another 50% on top of the base rate.
const KNOWLEDGE_BONUS_PER_LEVEL := 0.5

@onready var _walls_mesh: MeshInstance3D = $Walls
@onready var _walls_base_position: Vector3 = _walls_mesh.position
@onready var _dome_mesh: MeshInstance3D = $Dome
@onready var _dome_base_position: Vector3 = _dome_mesh.position
@onready var _knowledge_timer: Timer = $KnowledgeTimer


## Godot lifecycle hook: registers for lookup/hitbox-overlay groups, sets
## durability from its BuildingKinds entry, starts the knowledge trickle,
## and shows the freshly-placed "just started" construction visual.
func _ready() -> void:
	add_to_group("buildings")
	add_to_group("structures")
	_setup_durability()
	_knowledge_timer.timeout.connect(_on_knowledge_timer_timeout)
	_apply_construction_visual(0.0)

## Template Method hook (see BuildableStructure._apply_construction_visual):
## the Walls mesh scales AND repositions as it rises; the Dome (sitting on
## top of the Walls, same as Building's Roof) only repositions.
func _construction_meshes() -> Array:
	return [
		{"mesh": _walls_mesh, "base_position": _walls_base_position},
		{"mesh": _dome_mesh, "base_position": _dome_base_position, "scales": false},
	]

## Duck-typed by BuildingMenu (has_method("get_info_text")) to show a line
## of live status beyond the generic name/durability/ports fields.
func get_info_text() -> String:
	return "Knowledge: +%d every %d s" % [_knowledge_per_tick(), int(_knowledge_timer.wait_time)]

## This instance's current knowledge-per-tick, boosted by its own
## upgrade_level (see KNOWLEDGE_BONUS_PER_LEVEL).
func _knowledge_per_tick() -> int:
	return int(round(BASE_KNOWLEDGE_PER_TICK * (1.0 + upgrade_level * KNOWLEDGE_BONUS_PER_LEVEL)))

## Signal handler for KnowledgeTimer: deposits this tick's knowledge and
## pops a floating-text confirmation, same convention Blob harvesting uses.
func _on_knowledge_timer_timeout() -> void:
	if is_under_construction:
		return
	var amount := _knowledge_per_tick()
	GameManager.add_resource("knowledge", amount)
	Effects.spawn_floating_text(get_parent(), global_position + Vector3(0.0, 2.2, 0.0), "+%d knowledge" % amount, Effects.resource_color("knowledge"))
