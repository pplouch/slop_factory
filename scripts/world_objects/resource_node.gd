class_name ResourceNode
extends StaticBody3D
## A harvestable world object (tree or rock): holds a finite amount of one
## resource type, shrinks away when depleted, and grows back after a
## respawn delay so the map never runs permanently dry.
##
## A solid StaticBody3D rather than a trigger-only Area3D, so blobs
## physically collide with it and can't clip through the scenery while
## walking past.

@export var resource_type: String = "wood"
@export var max_amount: int = 60
@export var respawn_time: float = 45.0

## Resources remaining before this node depletes and goes on cooldown.
var amount: int

## The node's normal (pre-despawn) scale, remembered so _spawn can restore
## it exactly -- clusters give each node a random size, so this can't just
## be hardcoded to Vector3.ONE.
var _base_scale: Vector3 = Vector3.ONE


## Godot lifecycle hook: fills the node to capacity and makes it
## discoverable to World's harvest-order assignment (see World._issue_harvest_orders).
func _ready() -> void:
	amount = max_amount
	add_to_group("resource_nodes")
	GemSparkle.apply_to_emissive_meshes(self)

## Brings a depleted node back: grows it back in from nothing, re-enables
## its solid collision and pickability. Called after the respawn delay
## elapses in _deplete.
func _spawn() -> void:
	visible = true
	var tween := create_tween()
	tween.tween_property(self, "scale", _base_scale, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	set_collision_layer_value(3, true)
	add_to_group("resource_nodes")

## Takes a just-depleted node out of play: stops it from being targeted or
## physically collided with, then shrinks it away before hiding it (an
## instant vanish would read as a glitch rather than "this is spent").
func _despawn() -> void:
	remove_from_group("resource_nodes")
	set_collision_layer_value(3, false)
	_base_scale = scale
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await tween.finished
	visible = false

## Called by a harvesting blob once per tick. Removes up to `requested`
## from the remaining amount (returning however much was actually taken,
## which may be less than requested near depletion) and triggers depletion
## once it hits zero.
func harvest(requested: int) -> int:
	var taken: int = min(requested, amount)
	amount -= taken
	if amount <= 0:
		_deplete()
	return taken

## Runs the full despawn -> wait -> respawn cycle for a depleted node.
func _deplete() -> void:
	await _despawn()
	await get_tree().create_timer(respawn_time).timeout
	amount = max_amount
	_spawn()

## Re-applies a harvested amount saved by a previous Chunk.snapshot_state,
## right after this node's own _ready() (which unconditionally resets
## amount to max_amount) has already run as part of a chunk reload -- see
## ChunkManager's own header on why a regenerated chunk needs to resume
## where the player left it rather than looking freshly full again. Skips
## the despawn/respawn tweens _deplete uses (there's nothing to visually
## shrink away; this node never existed until this exact frame) but still
## restarts a full respawn_time countdown for an already-depleted node --
## deliberately not the exact remaining time it had before unloading, a
## small, safe-direction inaccuracy (never better for the player than
## staying would have been) rather than tracking partial respawn progress
## for what should be a rare edge case.
func restore_state(saved_amount: int) -> void:
	amount = saved_amount
	if amount <= 0:
		remove_from_group("resource_nodes")
		set_collision_layer_value(3, false)
		visible = false
		await get_tree().create_timer(respawn_time).timeout
		amount = max_amount
		_spawn()
