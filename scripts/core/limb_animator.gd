class_name LimbAnimator
extends RefCounted
## Stateless helper (static functions only) for the blocky, code-driven limb
## animation shared by Blob's humanoid rig and Enemy's humanoid/quadruped
## rigs -- no Skeleton3D/bones, matching this project's "everything built
## and animated in script" convention. Blob and Enemy each still own their
## *own* phase/timer fields and call these with their own pivot node
## references; only the actual math was duplicated before, not any shared
## state, so this stays a set of pure functions rather than a full object.

## Advances `phase` by one physics tick and applies the classic "opposite
## swing" walk cycle to two paired limbs (arms, or a quadruped's diagonal
## leg pair): `pivot_a`/`pivot_d` swing one way, `pivot_b`/`pivot_c` the
## other. Returns the updated phase for the caller to store.
static func apply_gait_swing(phase: float, delta: float, cycles_per_second: float, amplitude: float,
		speed: float, reference_speed: float,
		pivot_a: Node3D, pivot_b: Node3D, pivot_c: Node3D, pivot_d: Node3D) -> float:
	var new_phase: float = phase + delta * TAU * cycles_per_second * (speed / max(reference_speed, 0.01))
	var swing := sin(new_phase) * amplitude
	pivot_a.rotation.x = swing
	pivot_b.rotation.x = -swing
	pivot_c.rotation.x = -swing
	pivot_d.rotation.x = swing
	return new_phase

## Eases every pivot in `pivots` back toward its neutral rotation -- used
## whenever a rig isn't actively walking/harvesting (idle, holding position,
## between attacks) so it doesn't freeze mid-swing.
static func ease_to_rest(delta: float, reset_speed: float, pivots: Array) -> void:
	for pivot in pivots:
		pivot.rotation.x = lerp(pivot.rotation.x, 0.0, delta * reset_speed)

## Plays a quick forward-punch-and-recover tween on `pivot`, the shape used
## by both Blob's and Enemy's humanoid attack animation.
static func play_punch_swing(pivot: Node3D, duration: float) -> void:
	var tween := pivot.create_tween()
	tween.tween_property(pivot, "rotation:x", -1.1, duration * 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(pivot, "rotation:x", 0.0, duration * 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
