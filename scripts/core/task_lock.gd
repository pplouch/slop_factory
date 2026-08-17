class_name TaskLock
extends RefCounted
## Stateless helpers for counting how many blobs already have a given
## resource node or building as their current job -- used to spread a group
## order (or an auto-assigned worker) across multiple available targets
## instead of piling everyone onto the same one, without needing a
## separately-maintained lock/reservation counter that could desync if a
## blob dies, gets a fresh order that overrides its old target, or a
## building gets demolished mid-job. A count computed fresh from every
## blob's own pending_harvest_node/pending_build_target can never go stale
## the way a manually incremented/decremented counter could (see feature
## backlog: "units should select a task and lock it so others pursue a task
## that isn't locked" -- the previous gap was that each order-issuing call
## only tracked assignments made *within that same call*, so a second order
## issued later, or an unrelated auto-assignment, had no idea a node/
## building was already fully worked and would pile more blobs onto it
## anyway).

## Every target kind shares the same "don't crowd more than this many
## workers onto one thing" cap -- resource nodes (OrderManager's own
## MAX_BLOBS_PER_NODE previously) and buildings (BuildingManager's
## AUTO_ASSIGN_BUILDER_CAP previously) now both read this one constant so
## the two stay in sync by construction instead of by two separately-tuned
## magic numbers.
const MAX_WORKERS_PER_TARGET := 2

## How many blobs currently have `node` as their pending_harvest_node --
## Moving to it, actively Harvesting it, or looping back to it after a
## deposit trip (see Blob.pending_harvest_node/_deposit).
static func harvest_count(tree: SceneTree, node: Node) -> int:
	var count := 0
	for blob in tree.get_nodes_in_group("blobs"):
		if is_instance_valid(blob) and blob.pending_harvest_node == node:
			count += 1
	return count

## How many blobs currently have `building` as their pending_build_target
## (see Blob.pending_build_target/ConstructState).
static func build_count(tree: SceneTree, building: Node) -> int:
	var count := 0
	for blob in tree.get_nodes_in_group("blobs"):
		if is_instance_valid(blob) and blob.pending_build_target == building:
			count += 1
	return count
