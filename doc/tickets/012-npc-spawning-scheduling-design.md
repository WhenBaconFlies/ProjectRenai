# 012: NPC spawning & scheduling — Design

Companion to `doc/tickets/012-npc-spawning-scheduling.md`. Decisions are recorded in
`doc/idea-v1-decisions.md` under "Ticket 012".

## Approach

Data-first, mirroring the rest of v1: the instance schema and map markers are added
first, then a standalone spawner, then thin scene wiring in `Game.gd`. No AI movement
or dialogue is introduced — this ticket only proves that NPCs exist as instances,
attend class, and are addressable by a stable id that downstream tickets can use.

## Components

### `NpcInstance` (`scripts/NpcInstance.gd`, `class_name NpcInstance extends Resource`)

The single instance shape used by NPCs now and the player later:

- `instance_id: String` — stable per-save id (`npc:0`, `npc:1`, ...); the roster/record key.
- `template_id: String` — stable template id (`char:sam`, ...); never a path or UID.
- `display_name: String` — cached from the template for UI/log use.
- `stats: Dictionary` — current STR/DEX/CON/INT/WIS/CHA (base + deltas).
- `mood: int` — 0..100.
- `meters: Dictionary` — `{ other_id -> { familiarity: int, affection: int } }`.
- `schedule: Dictionary` — `{ period:int -> marker_name:String }`.
- `position: Vector2` — world-space position.
- `current_goal: String` — reserved for ticket 013.
- `tier: String` — unexported, runtime-only, default `"close"`; constants
  `TIER_CLOSE`/`TIER_NEAR`/`TIER_FAR` for post-v1 chunk loading.

Helpers: `from_template()`, `get_stat()`, `get_meter()` (creates a default meter),
`marker_for_period()`, `snapshot()/from_snapshot()` for ticket 017.

### Map markers (`scripts/Map.gd`, `resources/maps/map_school.tres`)

`markers: Dictionary` maps a name to a world-space `Vector2`. Read API:
`get_marker(name)`, `has_marker(name)`, `get_marker_names()`. Four markers are
authored on the school map: `classroom_a` (56,40), `classroom_b` (100,40),
`classroom_c` (56,88), `classroom_d` (100,88).

### `Npc` (`scripts/Npc.gd`, `class_name Npc extends CharacterBody2D`)

Holds an `NpcInstance`, joins group `npc`, draws a generated circle. `setup(instance)`
and `move_to(position)` keep the node and instance position in sync. The collider is
present so ticket 013 can attach a `NavigationAgent2D` without a node-type change.

### `NpcSpawner` (`scripts/NpcSpawner.gd`, `class_name NpcSpawner extends RefCounted`)

Pure/testable helper. `spawn(parent, map, template_ids) -> Array[Npc]`:

1. For each template id, resolve via `ModLoader.get_resource(TYPE_CHARACTER, id)`.
   A null result logs a warning, appends to `get_last_report()`, and skips only that
   NPC (recoverable).
2. Build an `NpcInstance` with `instance_id = "npc:%d"`, stats copied from the
   template, and a deterministic period→marker schedule rotated by NPC index.
3. Create an `Npc` node, add it to `parent`, place it at the map spawn point with a
   small horizontal offset so the initial group does not overlap.
4. Return the spawned NPCs; also expose `get_instances()` and `get_last_report()`.

### Scene wiring (`scripts/Game.gd`)

Before `TimeManager.start_day(1)`:

- spawn NPCs under an `Npcs` node using `NpcSpawner`;
- `TimeManager.set_roster("player", [npc instance ids...])`;
- `TimeManager.set_stats_provider()` backed by `NpcInstance.stats` (player falls back
  to `TimeManager.player_template_path`, matching ticket 011);
- connect `TimeManager.state_changed` so entering a class period sends NPCs to
  the instance's scheduled marker (falling back to the map spawn point with a
  warning). Originally this was an instant `Npc.move_to()`; user-approved change
  after ticket 013 makes NPCs walk there instead (`set_forced_destination()`),
  with `move_to()` retained as the skip-transition hard snap.

Because all of this happens in `Game._ready()` before `start_day()`, the initial
`PERIOD1` transition is observed and NPCs move to class immediately.

## Template resolution

`load_mods()` registers base character `.tres` files (from `res://resources/characters/`)
before mod content, so every available template is in the registry. Three new base
templates (`char_jordan`, `char_riley`, `char_taylor`) join `char:sam` to give four
distinct authored NPC templates, so the default NPC count does not depend on which
mods are enabled. `char:alex` is reserved for the player; the sample mod's
`char:mod_sample` remains registered as an optional extra for spawner callers.

## Acceptance mapping

| Checkbox | Covered by |
|----------|------------|
| 3–5 NPCs spawn from template IDs at map spawn | `NpcSpawner.spawn()` from 4 ids |
| Per-instance schedule (period → named marker) | `NpcInstance.schedule` + `Map.markers` |
| NPCs move to class location on period change | `Game._on_state_changed()` → class travel via `Npc.set_forced_destination()` (supersedes the original instant `Npc.move_to()`; skipped transitions still snap) |
| Attendance recorded per NPC per period | `TimeManager.set_roster()` + existing records |
| Template referenced by stable ID | `NpcInstance.template_id` |
| Runtime-only `tier` (default close) | unexported `NpcInstance.tier` |
| Missing template recoverable | spawner null-template branch + diagnostic |

## Verification plan

Headless Godot scripts assert: instance fields/tier default, 4 NPCs spawned, stable
unique instance ids, schedules reference real markers, period-change moves NPCs to
the correct marker, attendance records appear for each NPC id, template id linkage,
and no crash with a bogus template id. Plus a DebugStart → Game.tscn launch smoke test.
