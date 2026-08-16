class_name MaterialUtil
extends RefCounted
## Tiny named helper for a pattern repeated across several scripts:
## duplicate a mesh's material before recoloring it, so the recolor doesn't
## bleed into every other instance sharing the same base mesh resource.

static func duplicated_material(mesh_instance: MeshInstance3D) -> StandardMaterial3D:
	return mesh_instance.mesh.material.duplicate()
