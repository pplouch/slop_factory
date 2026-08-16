extends Node3D
## A fading ring that flashes at a point on the ground to confirm something
## just happened there (an order was accepted, a blob spawned in).
## Self-configuring and self-freeing -- spawn it via Effects.spawn_command_marker
## rather than instantiating scenes/command_marker.tscn directly.
##
## `color` must be set *before* this node enters the tree (Effects does
## this), since _ready() reads it immediately to build the ring's material.

@export var color: Color = Color(1, 1, 1, 1)

@onready var mesh: MeshInstance3D = $Mesh


## Godot lifecycle hook: tints a duplicated copy of the ring's material
## (so this doesn't recolor every other marker sharing the base mesh
## resource), then plays a scale-up + fade-out tween and frees itself once
## it finishes.
func _ready() -> void:
	var mat: StandardMaterial3D = MaterialUtil.duplicated_material(mesh)
	mat.albedo_color = color
	mat.emission = color
	mesh.set_surface_override_material(0, mat)

	scale = Vector3.ONE * 0.3
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ONE * 1.5, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tween.chain().tween_callback(queue_free)
