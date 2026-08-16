class_name BlobState
extends RefCounted
## Abstract base of the Blob state machine (State pattern).
##
## A Blob's behavior differs completely depending on what it is doing right
## now: standing around, walking somewhere, harvesting a resource node, or
## hauling loot home. Rather than branching on an enum inside one large
## function, each phase gets its own small class that only knows about
## itself.
##
## Blob acts as the "context": it holds a reference to the current state and
## forwards its per-physics-frame update to it. A state's [method physics_update]
## returns the BlobState to switch to next, or null to keep running as-is --
## that return value is the entire transition mechanism, no external state
## machine/table required.
##
## Subclasses override [method physics_update], and optionally
## [method enter] / [method exit] for one-time setup or teardown (e.g.
## resetting an internal timer when the state becomes active again).

## Called once, immediately after Blob switches into this state.
func enter(_blob: CharacterBody3D) -> void:
	pass

## Called once, immediately before Blob switches away from this state.
func exit(_blob: CharacterBody3D) -> void:
	pass

## Called every physics frame while this state is active.
## Return another BlobState instance to transition into it, or null to stay
## in this state for another frame.
func physics_update(_blob: CharacterBody3D, _delta: float) -> BlobState:
	return null

## Whether this state represents the blob actively travelling toward a
## destination. Blob's stall-detector (see blob.gd) only tracks movement
## progress while this is true, so states that don't move (Idle, Harvesting)
## simply leave this at its default of false.
func is_travelling() -> bool:
	return false
