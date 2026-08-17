extends Node
## Effects (Factory pattern, registered as an autoload singleton).
##
## Every transient visual-feedback object in the game -- floating pickup
## text, particle bursts, the fading ring that confirms an order was
## accepted -- used to be instantiated, configured, positioned and parented
## by hand at each call site (Blob, World, Building all had near-identical
## copies of that boilerplate). This script centralizes that construction
## logic behind a small set of intention-revealing methods, so gameplay
## scripts just say *what* effect they want and *where*, without knowing
## *how* it's built or how it cleans itself up.
##
## Also owns the one place that maps a resource type ("wood", "stone", ...)
## to a display color, since that's a presentation concern the gameplay
## scripts (Blob, resource nodes) shouldn't need to care about.

const FLOATING_TEXT_SCENE: PackedScene = preload("res://scenes/vfx/floating_text.tscn")
const IMPACT_PARTICLES_SCENE: PackedScene = preload("res://scenes/vfx/impact_particles.tscn")
const COMMAND_MARKER_SCENE: PackedScene = preload("res://scenes/vfx/command_marker.tscn")
const RESOURCE_ITEM_SCENE: PackedScene = preload("res://scenes/factory/resource_item.tscn")

const CHIRP_MIX_RATE := 22050
const CHIRP_DURATION := 0.14
const CHIRP_FREQ_RANGE := Vector2(700.0, 1150.0)

## Built once here (rather than loading a sound asset -- none exist in this
## project) and reused for every chirp; per-play pitch_scale randomization
## (see play_chirp) gives enough variety without needing several baked
## waveforms.
var _chirp_stream: AudioStreamWAV


## Godot lifecycle hook: bakes the shared chirp waveform.
func _ready() -> void:
	_chirp_stream = _build_chirp_stream()

## Synthesizes a short upward-sweeping sine chirp with a decaying envelope
## -- a "cute" critter blip built entirely from raw PCM samples, since no
## audio assets exist in this project.
func _build_chirp_stream() -> AudioStreamWAV:
	var sample_count := int(CHIRP_MIX_RATE * CHIRP_DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / CHIRP_MIX_RATE
		var progress := float(i) / sample_count
		var freq: float = lerp(CHIRP_FREQ_RANGE.x, CHIRP_FREQ_RANGE.y, progress)
		var envelope := pow(1.0 - progress, 2.0)
		var sample := sin(TAU * freq * t) * envelope
		data.encode_s16(i * 2, int(clamp(sample, -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = CHIRP_MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream

## Plays one instance of the shared chirp sound at `global_pos`, with a
## random pitch_scale (rather than a fixed pitch every time) so a crowd of
## blobs chirping doesn't sound like one sample copy-pasted. Self-frees
## once playback finishes.
func play_chirp(parent: Node, global_pos: Vector3, pitch_variance: float = 0.15) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = _chirp_stream
	player.pitch_scale = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	player.unit_size = 6.0
	player.volume_db = -6.0
	parent.add_child(player)
	player.global_position = global_pos
	player.play()
	player.finished.connect(player.queue_free)

## Spawns a floating label (e.g. "+3") that rises and fades out on its own,
## parented under `parent` at `global_pos`.
func spawn_floating_text(parent: Node, global_pos: Vector3, text: String, color: Color) -> void:
	var popup: Label3D = FLOATING_TEXT_SCENE.instantiate()
	parent.add_child(popup)
	popup.global_position = global_pos
	popup.text = text
	popup.modulate = color

## Spawns a one-shot, self-freeing particle burst at `global_pos`, tinted
## `color`. Used for harvest hits and building deposits.
func spawn_impact(parent: Node, global_pos: Vector3, color: Color, particle_amount: int = 8) -> void:
	var burst := IMPACT_PARTICLES_SCENE.instantiate()
	burst.particle_color = color
	burst.particle_amount = particle_amount
	parent.add_child(burst)
	burst.global_position = global_pos

## Spawns a fading ring marker at `global_pos`, used to confirm that a
## right-click order (or a blob spawning in) was accepted.
func spawn_command_marker(parent: Node, global_pos: Vector3, color: Color) -> void:
	var marker := COMMAND_MARKER_SCENE.instantiate()
	marker.color = color
	parent.add_child(marker)
	marker.global_position = global_pos

## Spawns a ResourceItem of `resource_type`/`amount` at `global_pos`, parented
## under `parent`. Used by Extractor and Processor to place a new item onto
## the conveyor system; the item is otherwise moved around by whichever
## BeltSegment currently holds it.
func spawn_resource_item(parent: Node, global_pos: Vector3, resource_type: String, amount: int) -> Node3D:
	var item := RESOURCE_ITEM_SCENE.instantiate()
	item.resource_type = resource_type
	item.amount = amount
	parent.add_child(item)
	item.global_position = global_pos
	return item

## Maps a resource type name to the color used to represent it in VFX and
## popup text. Falls back to white for any type without a dedicated look.
func resource_color(resource_type: String) -> Color:
	match resource_type:
		"wood":
			return Color(0.85, 0.65, 0.35)
		"stone":
			return Color(0.8, 0.82, 0.85)
		"planks":
			return Color(0.75, 0.55, 0.3)
		"ice_crystal":
			return Color(0.75, 0.9, 1.0)
		"obsidian":
			return Color(0.85, 0.4, 0.15)
		"knowledge":
			return Color(0.25, 0.65, 0.7)
		_:
			return Color(1, 1, 1)
