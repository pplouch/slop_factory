class_name PanelAutofit
extends RefCounted
## Stateless helper for the clamp-to-content-size math BuildingMenu and
## UnitInfoPanel both used to duplicate: take a computed "natural" size,
## clamp it between a fixed minimum and a viewport-fraction maximum. Each
## panel still computes its own `natural` size (BuildingMenu from one VBox,
## UnitInfoPanel by summing several sub-containers) and its own final
## `position` (centered vs. pinned to a screen corner) -- those genuinely
## differ per panel and stay in each caller.

static func resolve_size(natural: Vector2, min_size: Vector2, max_fraction: Vector2, viewport_size: Vector2) -> Vector2:
	var max_size := Vector2(viewport_size.x * max_fraction.x, viewport_size.y * max_fraction.y)
	return Vector2(
		clamp(natural.x, min_size.x, max_size.x),
		clamp(natural.y, min_size.y, max_size.y)
	)
