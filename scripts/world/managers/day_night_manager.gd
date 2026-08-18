class_name DayNightManager
extends RefCounted
## Tracks elapsed play time as an in-game day/night cycle (purely visual --
## adjusts the sun light and sky color, no gameplay ever reads it besides
## triggering the wave below) and spawns a periodic "wave" of extra enemies
## converging on the player's base every WAVE_INTERVAL_DAYS (see feature
## backlog: "add a day/night cycle, and every 7 days a huge wave of enemies
## come to attack your town hall"). Split out of world.gd like every other
## manager (see CLAUDE.md's "world.gd -- the central controller" section).
##
## DAY_LENGTH_SECONDS is an arbitrary pacing choice -- nothing in the
## backlog specified one -- picked short enough that a single sit-down
## session sees several day/night transitions and at least one wave,
## rather than a cycle so slow it never completes or so fast it just reads
## as flickering.

const DAY_LENGTH_SECONDS := 300.0
const WAVE_INTERVAL_DAYS := 7

## The game now starts already at noon (see setup()) instead of at t=0
## (midnight, current_day()'s own day-boundary point) -- starting at
## midnight meant every fresh session opened in near-darkness, which read
## as a bug ("it looks like night during the day") rather than the
## intended day/night cycle actually working.
const START_TIME_FRACTION := 0.5

# -- Visual tuning: sun energy/color and sky brightness across the cycle --
## Bumped well past a bare-default DirectionalLight3D's energy=1.0 -- at
## this project's steep top-down RTS camera angle, with no other light
## source in the scene, 1.0 alone read as dim/flat rather than a bright
## sunny day (see feature request: "daytime to be more light, it looks
## like it's night when it's daytime actually").
const DAY_LIGHT_ENERGY := 1.15
const NIGHT_LIGHT_ENERGY := 0.18
const DAY_LIGHT_COLOR := Color(1.0, 0.98, 0.92)
const NIGHT_LIGHT_COLOR := Color(0.55, 0.6, 0.85)
const DAY_SKY_TOP := Color(0.38, 0.58, 0.9)
const NIGHT_SKY_TOP := Color(0.02, 0.03, 0.08)
const DAY_SKY_HORIZON := Color(0.78, 0.82, 0.87)
const NIGHT_SKY_HORIZON := Color(0.05, 0.05, 0.12)

# -- Wave spawn tuning --
const WAVE_ENEMY_COUNT := 18
const WAVE_SPAWN_RADIUS := 14.0
const WAVE_WARNING_COLOR := Color(1.0, 0.3, 0.25)

var _elapsed_seconds := 0.0
## The last day a wave was actually spawned for -- guards against spawning
## more than once for the same day (process() may run this check many
## times across the day's own length before current_day() ticks over).
var _last_wave_day := 0

var _world: Node3D
var _sun: DirectionalLight3D
var _sky_material: ProceduralSkyMaterial


func setup(world: Node3D, sun: DirectionalLight3D, sky_material: ProceduralSkyMaterial) -> void:
	_world = world
	_sun = sun
	_sky_material = sky_material
	_elapsed_seconds = DAY_LENGTH_SECONDS * START_TIME_FRACTION
	# Applied immediately (rather than waiting for the first process() call
	# next frame) so the very first rendered frame already shows full noon
	# brightness instead of one frame of the sun/sky's pre-cycle engine
	# defaults.
	_apply_lighting()

## Godot per-frame hook (called from World._process): advances the clock,
## refreshes lighting, and checks whether a new wave day has just arrived.
func process(delta: float) -> void:
	_elapsed_seconds += delta
	_apply_lighting()
	var day := current_day()
	if day > _last_wave_day and day % WAVE_INTERVAL_DAYS == 0:
		_last_wave_day = day
		_spawn_wave()

## Which in-game day this is (1-based) -- day 1 is the whole first
## DAY_LENGTH_SECONDS.
func current_day() -> int:
	return int(_elapsed_seconds / DAY_LENGTH_SECONDS) + 1

## 0..1 position within the current day -- 0/1 is midnight (the day
## boundary current_day() itself ticks over at), 0.5 is noon, matching
## _apply_lighting's own cosine curve (brightness bottoms out at t=0/1,
## peaks at t=0.5). Used both for lighting interpolation and HUD.gd's own
## day/time readout.
func time_of_day_fraction() -> float:
	return fmod(_elapsed_seconds, DAY_LENGTH_SECONDS) / DAY_LENGTH_SECONDS

## True during the "night" portion of the cycle, straddling the midnight
## boundary (t=0/1, see time_of_day_fraction) rather than centered on it --
## true for the last quarter of one day and the first 15% of the next.
func is_night() -> bool:
	var t := time_of_day_fraction()
	return t < 0.15 or t > 0.75

## Debug helper (see DebugMenu's time-of-day buttons): jumps straight to
## `fraction` (0..1, see time_of_day_fraction) within the *current* day --
## preserves current_day()'s own running count rather than resetting it --
## and re-applies lighting immediately rather than waiting for the next
## process() call, so a tester sees the change the instant the button is
## pressed.
func set_time_fraction(fraction: float) -> void:
	var day_index := current_day() - 1
	_elapsed_seconds = (day_index + clamp(fraction, 0.0, 0.999)) * DAY_LENGTH_SECONDS
	_apply_lighting()

## Smoothly interpolates the sun's energy/color and the sky's colors across
## the day/night cycle using a single cosine-shaped brightness curve (peaks
## at noon, bottoms out at midnight) rather than a hard day/night switch or
## linear ramps with a visible "corner" at dawn/dusk.
func _apply_lighting() -> void:
	var t := time_of_day_fraction()
	var brightness: float = (cos((t - 0.5) * TAU) + 1.0) * 0.5
	if _sun:
		_sun.light_energy = lerp(NIGHT_LIGHT_ENERGY, DAY_LIGHT_ENERGY, brightness)
		_sun.light_color = NIGHT_LIGHT_COLOR.lerp(DAY_LIGHT_COLOR, brightness)
	if _sky_material:
		_sky_material.sky_top_color = NIGHT_SKY_TOP.lerp(DAY_SKY_TOP, brightness)
		_sky_material.sky_horizon_color = NIGHT_SKY_HORIZON.lerp(DAY_SKY_HORIZON, brightness)

## Spawns WAVE_ENEMY_COUNT enemies in a ring around the player's Town Hall
## (or the map origin, where founder blobs start, if none has been built
## yet) -- Enemy's own AI already chases whatever blob is nearest within
## DETECTION_RANGE, so a ring landing near the player's base converges on
## and fights the blobs defending it without needing a separate "damage
## buildings directly" mechanic, a bigger AI change the backlog item didn't
## specifically call for. Kind is picked from the *entire* EnemyKinds
## roster rather than just a local chunk's own biome list, for real wave
## variety; GameManager's existing enemy-difficulty scaling (already
## growing with playtime, see Enemy._ready) makes each successive wave
## tougher automatically, with no extra scaling needed here.
func _spawn_wave() -> void:
	var center := _find_town_hall_position()
	var kind_ids := EnemyKinds.get_ordered_ids()
	for i in WAVE_ENEMY_COUNT:
		var angle := (TAU / WAVE_ENEMY_COUNT) * i
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * WAVE_SPAWN_RADIUS
		var spawn_pos := center + offset
		var enemy: Node3D = SpawnManager.ENEMY_SCENE.instantiate()
		enemy.kind_id = kind_ids.pick_random()
		# difficulty_multiplier must be set before add_child -- see Enemy's
		# own header on why it can't just read global_position in _ready().
		enemy.difficulty_multiplier = Biomes.enemy_difficulty_multiplier_at(spawn_pos.x, spawn_pos.z)
		_world.add_child(enemy)
		enemy.global_position = spawn_pos
	Effects.spawn_floating_text(_world, center + Vector3(0.0, 2.0, 0.0), "A wave of enemies approaches!", WAVE_WARNING_COLOR)

## The player's Town Hall position if one has been built, else the map
## origin (where founder blobs start and no Town Hall may exist yet).
func _find_town_hall_position() -> Vector3:
	for building in _world.get_tree().get_nodes_in_group("buildings"):
		if "kind_id" in building and building.kind_id == "town_hall":
			return building.global_position
	return Vector3.ZERO
