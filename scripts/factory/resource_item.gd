extends Node3D
## A single discrete unit of a resource riding the conveyor system: created
## by an Extractor or Processor, moved along by whichever BeltSegment
## currently holds it (see BeltSegment._update_item_position), and finally
## either consumed by a Processor's input or auto-collected into
## GameManager's stockpile at the end of a belt line.
##
## `resource_type` must be set *before* this node enters the tree (whoever
## spawns it does this), since _ready() reads it immediately to tint the mesh.

@export var resource_type: String = "wood"
@export var amount: int = 1

@onready var mesh_instance: MeshInstance3D = $Mesh


## Godot lifecycle hook: tints this item's mesh to match its resource type,
## so different resources are visually distinguishable riding the same
## belts. Duplicates both the mesh and its material (rather than using a
## surface override on the shared mesh resource) -- a brand-new
## PrimitiveMesh applying a surface override immediately on the same frame
## it's created can trip up the renderer's material bookkeeping, since the
## mesh's own RenderingServer-side registration hasn't settled yet; giving
## this instance its own fully-owned mesh+material sidesteps that.
func _ready() -> void:
	var unique_mesh: BoxMesh = mesh_instance.mesh.duplicate()
	var mat: StandardMaterial3D = unique_mesh.material.duplicate()
	mat.albedo_color = Effects.resource_color(resource_type)
	unique_mesh.material = mat
	mesh_instance.mesh = unique_mesh
