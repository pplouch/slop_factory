extends Label3D
## A short-lived "+N"-style label that rises and fades out on its own.
## Spawn it via Effects.spawn_floating_text rather than instantiating
## scenes/floating_text.tscn directly.

const LIFETIME := 0.5
const RISE_SPEED := 1.6

## Seconds elapsed since this popup was created.
var _age := 0.0


## Godot per-frame hook: drifts the label upward and fades it out linearly
## over LIFETIME seconds, freeing it once fully transparent.
func _process(delta: float) -> void:
	_age += delta
	global_position.y += RISE_SPEED * delta
	modulate.a = clamp(1.0 - (_age / LIFETIME), 0.0, 1.0)
	if _age >= LIFETIME:
		queue_free()
