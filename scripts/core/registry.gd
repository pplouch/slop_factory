class_name Registry
extends Node
## Base class for the project's data-driven catalogs (Registry pattern):
## BlobKinds, EnemyKinds, and BuildingKinds all used to hand-roll the exact
## same `_kinds`/`_ordered_ids` storage, `_register()`, and
## `get_ordered_ids()` -- only their `Kind` inner class shape and their
## `get_kind()` fallback policy actually differed. This holds the shared
## part; subclasses just define their own `Kind` class and call `_register`
## from their own `_ready()`.

var _kinds: Dictionary = {}
var _ordered_ids: Array = []

## Empty string (the default) means "no fallback -- return null for an
## unknown id" (BuildingKinds' behavior: it must distinguish "not a
## building" from "unknown id"). A subclass that wants unknown ids to
## resolve to a specific known entry instead (BlobKinds falling back to
## "worker", EnemyKinds to "slime") sets this in its own `_ready()` before
## or after registering.
var _default_id: String = ""


## Adds `kind` to the catalog, preserving registration order for UI display.
func _register(kind) -> void:
	_kinds[kind.id] = kind
	_ordered_ids.append(kind.id)

## Returns the Kind for `id`, honoring `_default_id`'s fallback policy.
func get_kind(id: String):
	if _default_id == "":
		return _kinds.get(id, null)
	return _kinds.get(id, _kinds.get(_default_id))

## Every registered id, in registration order -- what UI code iterates to
## build rows without needing to know a registry's concrete Kind shape.
func get_ordered_ids() -> Array:
	return _ordered_ids
