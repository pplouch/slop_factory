extends ColorRect
## The translucent drag-select rectangle drawn while the player is
## box-selecting blobs. Purely visual -- World does the actual hit-testing
## against blob screen positions; this just needs to look like a rectangle
## is being dragged.

## Godot lifecycle hook: starts hidden and ensures this overlay never
## intercepts mouse input meant for the 3D world underneath it.
func _ready() -> void:
	visible = false
	color = Color(0.4, 0.85, 1.0, 0.18)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Shows the rectangle spanning corners `a` and `b` (in either order),
## called continuously while the mouse drags.
func show_rect(a: Vector2, b: Vector2) -> void:
	visible = true
	position = Vector2(min(a.x, b.x), min(a.y, b.y))
	size = Vector2(abs(a.x - b.x), abs(a.y - b.y))

## Hides the rectangle once the drag ends.
func hide_rect() -> void:
	visible = false
	size = Vector2.ZERO
