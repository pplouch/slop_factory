# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A Godot 4.7 (GDScript) 3D top-down idle/incremental game — working title "Rogue idle slop factory survivor rpg ultimate". A single scene (`world.tscn`) procedurally generates a map, spawns "blob" worker units the player commands with RTS-style click/drag selection, gathers resources into a shared stockpile, and layers on building upgrades, hireable unit archetypes, a wandering enemy with reactive combat, and a grid-based factory-automation subsystem (extractors/belts/processors) toggled via an in-game build mode.

## Running and validating

There is no test suite (GUT/gdUnit are not installed) and no build step — GDScript runs directly. Godot's own CLI is the only validation tool available, and is the primary way to catch mistakes without opening the editor:

- **Import/parse check** (catches script syntax errors, bad `class_name`/autoload registration, broken resource references):
  `<godot> --headless --path . --import --quit`
- **Headless runtime smoke test** (actually runs `_ready`/`_process`/`_physics_process` for N frames and prints runtime errors):
  `<godot> --headless --path . res://world.tscn --quit-after <N>`
  - Add `--fixed-fps 60` to decouple simulated time from wall-clock time, so e.g. a 60-second building-spawn timer or a 45-second resource-respawn timer can be exercised in a couple of real seconds.
- Some bugs (material/shader errors) only reproduce under a real graphics driver, not the headless dummy renderer — when in doubt, also run once **without** `--headless` (it won't exit on its own; kill the process after a few seconds).
- There's no way to simulate mouse/keyboard input headlessly. To validate anything mouse-driven (selection, build-mode placement), call the underlying `world.gd` methods directly (e.g. `_try_place_structure()`, `_issue_harvest_orders()`) rather than synthesizing `InputEvent`s.
- Typical validation loop: temporarily wire a `_debug_*` method to a `get_tree().create_timer(...).timeout` in `world.gd`'s `_ready()`, run headless, read the printed output, then remove the debug code before finishing.
- On this machine the Godot 4.7.1 binary is a portable install at `~/Downloads/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe` — note it unpacked into a directory with the same name as the zip, so the real executables are one level inside, not the top-level path itself.

## Architecture

### Autoload singletons (`res://scripts/*.gd`, registered in `project.godot [autoload]`)

- **`GameManager`** — sole source of truth for the resource stockpile (`wood`/`stone`/`planks`, arbitrary string keys) and the 5 building upgrades (`speed`/`strength`/`efficiency`/`capacity`/`growth`). All spending goes through `try_purchase_upgrade`/`try_spend_wood`; nothing else mutates `resources`/`upgrade_levels` directly. Emits `resource_changed`/`upgrade_changed` — HUD, BuildingMenu, and every Blob react to these instead of polling.
- **`Effects`** — factory for every transient VFX object (floating damage/pickup text, particle bursts, order-confirmation rings, conveyor `ResourceItem`s) plus the one place that maps a resource type to a display color. Gameplay scripts never instantiate these scenes directly.
- **`BlobKinds`** — small data-driven registry of the four hireable unit archetypes (worker/scout/hauler/brute) and their stat multipliers/hire cost/look. Adding a kind is one call in `blob_kinds.gd`'s `_ready()`; BuildingMenu's hire rows are generated from `get_ordered_ids()`, so nothing else needs to change.

### `world.gd` — the central controller

Owns everything that isn't a self-contained actor: procedural map generation (tree/rock clusters, ambient enemy population), all mouse/keyboard input routing (`_unhandled_input` branches into normal play, or into build-mode input if `_build_mode_active`), unit selection state, and the factory-placement grid (`_grid_structures: Dictionary[Vector2i, Node]`, exposed via `grid_to_world` / `world_to_grid` / `get_structure_at` / `register_structure` so belts/extractors/processors can look up their neighbors without holding direct references to each other).

UI panels (`HUD`, `BuildingMenu`, `BuildPalette`, `DebugMenu`) are dumb views: they only emit signals (`toggle_requested`, `kind_selected`, etc.) and expose `set_active`/`open_menu`-style setters. `world.gd` owns all the actual logic and wires to their signals in `_ready()`.

### Blob: State pattern (`scripts/blob.gd` + `scripts/blob_states/`)

A Blob's per-frame behavior is delegated to `current_state.physics_update(self, delta)`, where `current_state` is one of `IdleState`/`MovingState`/`HarvestingState`/`ReturningState` (each a `RefCounted` with `class_name`, so no preloading is needed). A state's `physics_update` returns the next `BlobState` to transition into, or `null` to stay — that return value is the entire transition mechanism. `blob.gd` itself only holds what's genuinely shared across states (movement stepping, stall-recovery, inventory, stats); the states hold just the branching logic for their own phase and call back into `blob`'s helper methods.

### Combat: `Combatant` base class (`scripts/combatant.gd`)

`Blob` and `Enemy` both `extends Combatant`, which owns health/regen/evasion math and `take_damage()`. Damage feedback is a template method (`_show_damage_feedback`): Combatant's default is a neutral/rewarding look, used as-is by `Enemy` (the player hurting an enemy is good news); `Blob` overrides it with a more alarming red flash, since a blob taking damage is bad news. Combat is reactive, not proactive — a Blob keeps doing its job and only fights back if an enemy comes within its own short attack range; it never chases.

### Factory automation (`scripts/factory/`, grid-based)

`Extractor` (auto-harvests a linked resource node), `BeltSegment` (carries one `ResourceItem` at a time), and `Processor` (fixed recipe: 2 wood → 1 plank) all register onto `world.gd`'s grid via `register_structure`, and hand items to each other by calling `get_structure_at(my_cell + facing)` and checking `has_method("try_receive_input")`. A belt (or processor output) with nothing in the next cell auto-delivers straight to `GameManager`'s stockpile — that "end of the line" rule means a conveyor chain never needs to visibly terminate at a building. Placement goes through `world.gd`'s build-mode ghost preview (`_is_placement_valid` gates cost/occupancy/extractor-must-be-near-a-resource-node checks) before anything is actually instantiated.

### Physics layers (`project.godot [layer_names]`)

A project-wide convention, not just a `world.gd` detail: layer 1 = Ground, 2 = Blobs, 3 = Resources (also used for buildings and factory structures — anything solid blobs should path around, distinguished by group membership rather than layer), 4 = Enemies. Raycasts and `collision_mask`s throughout the project assume these bit values.

## Load-bearing conventions and gotchas

- **Set `@export` properties before `add_child()`.** Every dynamically-spawned scene (`Blob.kind_id`, `CommandMarker.color`, `ImpactParticles.particle_color`, `ResourceItem.resource_type`, factory structures' `facing`) reads its exported properties inside `_ready()`, which runs synchronously the moment the node enters the tree. Setting a property *after* `add_child()` is a real bug, not just bad style.
- **Never scale a dynamic physics body (`CharacterBody3D`) itself to zero.** A pop-in/pop-out animation must target a purely-cosmetic child node (see `Blob.visuals`). Scaling the body directly produces a degenerate transform Jolt cannot simulate and can permanently corrupt it. (Scaling a `StaticBody3D`'s own root — as `ResourceNode` does for its deplete/respawn animation — is fine; it isn't actively simulated the same way.)
- **Don't trust `velocity` after `move_and_slide()` to reflect real progress.** In this project's Jolt setup it can stay pinned at the input value even when a body is fully blocked. `Blob`'s stall-detector (`_update_stall_detection`) instead samples actual position displacement over a rolling window and kicks off a sideways detour (escalating distance/duration on repeated failure) if it isn't moving.
- **`add_child()` on a still-constructing parent fails.** `Building._ready()` spawning its initial crew must use `call_deferred`, since `World` (its parent) is still instantiating its own children at that point.
- **Ground is deliberately absent from Blob/Enemy collision masks**, and `global_position.y` is force-clamped to `0.0` every physics frame for both — this project has no vertical gameplay, and the clamp exists specifically to counteract drift introduced when several physics bodies get wedged together.
- **A freshly-created `PrimitiveMesh` applying a `surface_material_override` the same frame it's instantiated can trigger a real (reproduces outside headless too) "Parameter material is null" rendering-server error.** Fix used throughout: duplicate the mesh resource itself and set its `material` property directly (see `ResourceItem._ready()`) instead of overriding a surface on a shared mesh.
- **Right-click harvest orders spread a squad across up to `MAX_BLOBS_PER_NODE` nearby same-type resource nodes** (see `World._issue_harvest_orders`), each with a deterministic, evenly-spaced approach angle rather than a random one — a deliberate fix for blobs jamming each other when several were sent to the same tree.
