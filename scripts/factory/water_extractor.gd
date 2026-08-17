extends StaticBody3D
## Placeable-only-on-water counterpart to Extractor -- a stub for now (no
## actual water-harvesting logic), added alongside the other new-building
## stubs in CLAUDE.md's feature backlog as "logic not required yet". What
## *is* implemented is the build-mode UX its backlog entry actually calls
## for: BuildingManager.is_placement_valid restricts this kind to water
## tiles (Biomes.is_water_at) the way Extractor is restricted to standing
## near a resource node, and BuildingManager's water-extractor range
## indicators mirror Extractor's own range-indicator pattern -- adapted for
## continuous terrain (a local scan around the build-mode cursor) rather
## than a fixed list of discrete resource-node instances, since water has
## no per-instance node for a global indicator list to anchor to.
##
## No `facing` export, unlike Extractor -- there's no output side to orient
## yet, so BuildingManager.try_place_structure's `if "facing" in node` guard
## just skips rotating this one.
##
## Not a BuildingKinds entry -- same reasoning as Extractor/Processor (an
## always-available grid piece, no tech-tree gating, priced through
## BuildingManager.BUILD_COSTS instead).

## Duck-typed for BuildingMenu's generic "This Building" info section, same
## as Extractor/Wall/Belt -- not a BuildingKinds entry.
var kind_id := "water_extractor"
var display_name := "Water Extractor"


func _ready() -> void:
	add_to_group("structures")

## Duck-typed by BuildingMenu (has_method("get_info_text")) to show a line
## of live status beyond the generic name/durability/ports fields.
func get_info_text() -> String:
	return "Not yet functional -- placement only"
