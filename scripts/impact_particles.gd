extends GPUParticles3D
## A one-shot, self-configuring particle burst (harvest hits, deposit
## "cha-ching"). Builds its own mesh and process material entirely in code
## rather than via hand-authored sub-resources, so the only thing a caller
## needs to set is color/amount before adding it to the tree. Spawn it via
## Effects.spawn_impact rather than instantiating scenes/impact_particles.tscn
## directly.
##
## The @export values must be set *before* this node enters the tree
## (Effects does this), since _ready() reads them immediately to build the
## particle setup.

@export var particle_color: Color = Color.WHITE
@export var particle_amount: int = 8
@export var particle_spread_deg: float = 50.0
@export var particle_speed: float = 1.6


## Godot lifecycle hook: constructs a small unshaded, alpha-blended sphere
## mesh and a matching process material (upward burst with gravity pulling
## it back down), fires the one-shot emission, then frees this node once
## the burst has had time to fully play out.
func _ready() -> void:
	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.055
	particle_mesh.height = 0.11

	var mat := StandardMaterial3D.new()
	mat.albedo_color = particle_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mesh.material = mat

	var process_mat := ParticleProcessMaterial.new()
	process_mat.direction = Vector3(0.0, 1.0, 0.0)
	process_mat.spread = particle_spread_deg
	process_mat.initial_velocity_min = particle_speed * 0.6
	process_mat.initial_velocity_max = particle_speed
	process_mat.gravity = Vector3(0.0, -4.5, 0.0)
	process_mat.scale_min = 0.5
	process_mat.scale_max = 1.1
	process_mat.color = particle_color

	draw_pass_1 = particle_mesh
	process_material = process_mat
	amount = particle_amount
	lifetime = 0.5
	one_shot = true
	explosiveness = 0.9
	emitting = true

	await get_tree().create_timer(1.0).timeout
	queue_free()
