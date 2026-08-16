class_name Animal
extends ResourceNode
## A wandering food source: behaves exactly like any other ResourceNode
## (harvestable, depletes, respawns) but drifts slowly around a small home
## patch instead of sitting still, so the map's animals read as living
## creatures rather than another static prop.
##
## Deliberately a *small* wander radius (not a full Enemy-style roam) --
## World's harvest-order approach-point math assumes a resource node is
## roughly stationary, so an animal needs to stay close enough to wherever
## it was last clicked for a blob's approach point to still land nearby.

const WANDER_RADIUS := 2.0
const WANDER_INTERVAL_RANGE := Vector2(3.0, 7.0)
const WANDER_DURATION := 2.0

var _home: Vector3 = Vector3.ZERO
var _wander_timer: Timer


## Godot lifecycle hook: keeps ResourceNode's own setup (fills to capacity,
## joins "resource_nodes"), then starts the periodic wander tween.
func _ready() -> void:
	super._ready()
	_home = global_position
	_wander_timer = Timer.new()
	_wander_timer.wait_time = randf_range(WANDER_INTERVAL_RANGE.x, WANDER_INTERVAL_RANGE.y)
	_wander_timer.timeout.connect(_on_wander_timer_timeout)
	add_child(_wander_timer)
	_wander_timer.start()

## Tweens to a new nearby point within WANDER_RADIUS of home, then reloads
## the timer for the next wander. Skips the wander entirely while depleted
## (despawned animals shouldn't visibly slide around off-screen).
func _on_wander_timer_timeout() -> void:
	_wander_timer.wait_time = randf_range(WANDER_INTERVAL_RANGE.x, WANDER_INTERVAL_RANGE.y)
	if visible and amount > 0:
		var angle := randf() * TAU
		var r := randf() * WANDER_RADIUS
		var target := _home + Vector3(cos(angle) * r, 0.0, sin(angle) * r)
		var tween := create_tween()
		tween.tween_property(self, "global_position", target, WANDER_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
