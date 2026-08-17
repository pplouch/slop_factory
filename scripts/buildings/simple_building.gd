extends BuildableStructure
## Generic "stub" building script shared by every BuildingKinds entry that
## has no functional behavior of its own yet (Research Center, Patch of
## Vegetables, School, Tavern, House as of this writing -- see CLAUDE.md's
## feature backlog) -- just construction, upgrades, and durability, all
## already provided by BuildableStructure. The only thing that actually
## differs between two stub buildings is which scene/mesh they use, so
## rather than five near-identical scripts each hand-listing their own
## @onready mesh references (like Wall/WaterTank/Building do), this collects
## every direct MeshInstance3D child automatically.
##
## Positions are cached once in _ready(), NOT re-read live inside
## _construction_meshes() -- BuildableStructure._apply_construction_visual
## repositions each mesh's `position.y` based on `base_position` every time
## construction progresses, so if `base_position` were re-derived from the
## mesh's own (already-repositioned) current position on every call, each
## construction tick would re-base off the previous tick's shrunk position
## instead of the original, compounding toward zero instead of rising
## correctly.

var _mesh_children: Array = []
var _base_positions: Array = []


func _ready() -> void:
	add_to_group("buildings")
	add_to_group("structures")
	_setup_durability()
	for child in get_children():
		if child is MeshInstance3D:
			_mesh_children.append(child)
			_base_positions.append(child.position)
	_apply_construction_visual(0.0)

## Template Method hook (see BuildableStructure._apply_construction_visual).
func _construction_meshes() -> Array:
	var result: Array = []
	for i in _mesh_children.size():
		result.append({"mesh": _mesh_children[i], "base_position": _base_positions[i]})
	return result
