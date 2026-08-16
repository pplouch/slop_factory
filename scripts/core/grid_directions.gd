class_name GridDirections
extends RefCounted
## Shared constant for the 4 cardinal grid-cell offsets used by anything
## that checks its own neighbors (BeltSegment/Wall's `refresh_connections`,
## and World's own grid code) -- was previously declared identically in
## both BeltSegment and Wall. The neighbor-*test* logic itself (does a
## neighbor exist at all vs. is it specifically another Wall) and any
## rotation remapping stay in each caller, since those genuinely differ.

const CARDINAL_OFFSETS := {
	"pos_x": Vector2i(1, 0),
	"neg_x": Vector2i(-1, 0),
	"pos_z": Vector2i(0, 1),
	"neg_z": Vector2i(0, -1),
}
