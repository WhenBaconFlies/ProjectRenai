# 013: NPC goal-driven AI movement (free time) — Design

Companion to `doc/tickets/013-npc-goal-driven-ai.md`. Decisions are recorded in
`doc/idea-v1-decisions.md` under "Ticket 013".

## Approach

Data-first and testable, mirroring tickets 011/012: extend the `Map` and
`NpcInstance` schemas first, add a pure goal-selection helper (`NpcAi`), then add
`NavigationAgent2D` movement to the existing `Npc` node, then thin wiring in
`Game.gd` that enables AI only during `FREETIME*`. No dialogue or NPC-initiated
interactions are added — ticket 016 owns those, and `Npc.is_busy()` is the seam.

Goals are **interest + mood only** in v1; relationship-meter goals are deferred to
014/015 (user-approved) because directed meters are empty until those tickets.

## Components

### `Map` extensions (`scripts/Map.gd`, `resources/maps/map_school.tres`)

- `hangout_interests: Dictionary` — maps a hangout marker name to a
  `PackedStringArray` of interest ids/tags (e.g. `trait:likes_sports`, `sports`).
- `get_hangout_marker_names() -> Array` — sorted names from `markers` beginning
  with `hangout_`.
- `get_hangout_interests(name) -> PackedStringArray` — tags for a hangout.

Four hangout markers are authored on `map_school.tres`, separate from the four
`classroom_*` schedule markers: `hangout_library`, `hangout_courtyard`,
`hangout_garden`, `hangout_cafeteria`. All sit inside the baked navmesh and clear
of placed-object colliders.

### `NpcInstance` extensions (`scripts/NpcInstance.gd`)

- `current_goal: String` — now used; structured form `"hangout:<marker_name>"`
  (empty while idle).
- `goal_destination: Vector2` — new exported field, included in
  `snapshot()`/`from_snapshot()` so ticket 017 can restore in-flight goals.

### `NpcAi` (`scripts/NpcAi.gd`, `class_name NpcAi extends RefCounted`)

Pure, headless-testable goal selection:

1. Collect preference keys from `template.traits` in every category except
   `dislike` (authored characters express preferences via `skill` and
   `personality` traits too): both each `Trait.id` and every tag.
2. For each hangout marker, compute a weight: base 1, `+3` when a hangout interest
   matches an interest key, `+2` more for a `quiet` hangout when mood `< 40`, and
   `+2` more for an interest match when mood `>= 60`.
3. Pick a weighted-random hangout with a `RandomNumberGenerator` seeded from
   `instance_id.hash()`, the day/period and a re-evaluation counter, so
   re-evaluations are reproducible.
4. `relationship_candidates()` is a documented hook returning an empty array in
   v1; tickets 014/015 add seek/avoid here.

`select_goal()` returns `{"goal": String, "destination": Vector2}` and never
touches the scene tree or autoload globals.

### `Npc` movement (`scripts/Npc.gd`)

- Owns a child `NavigationAgent2D` (desired distances tuned to the body radius).
- `set_ai_enabled(enabled, map, seed_period)` starts/stops AI. Enabling evaluates a
  goal immediately; disabling clears `current_goal`, stops the agent and zeroes
  velocity.
- `evaluate_goal(map, seed_period)` calls `NpcAi`, writes `current_goal` and
  `goal_destination` to the instance, and sets the agent target.
- `_physics_process(delta)`: follow `get_next_path_position()` with
  `move_toward`-smoothed velocity and `move_and_slide()`, mirror position into the
  instance, and re-evaluate on arrival. If the path is empty/unreachable or no
  progress is made within a timeout, steer straight toward the destination for a
  short grace period, then re-evaluate — so NPCs never freeze. The no-progress
  flag (`_force_fallback`) persists independently of path availability, so a
  "usable" nav path cannot silently cancel stall recovery. When
  `move_and_slide()` reports a solid collision, steer along the collider tangent
  most aligned with the goal for a short beat before resuming the nav path. This
  is needed because the authored navmesh polygons overlap furniture colliders,
  so nav paths can lead straight into a bench/desk.
- `is_busy()` returns true while a goal is active (ticket 016 seam).

### Scene wiring (`scripts/Game.gd`)

- entering `FREETIME1/2/3`: reset the travel guard and call
  `set_ai_enabled(true, _map, day_number)` for each NPC;
- `_process()` during free time: once `get_phase_duration() - get_phase_elapsed()
  <= class_travel_lead_sec` (default 4 s), call
  `npc.set_forced_destination("class:<marker>", marker_position)` for every NPC.
  This reuses the navigation agent, obstacle sliding and stall recovery, but
  snaps exactly onto the marker on arrival;
- class entry: let an already-issued walk finish, or start one if the lead window
  was missed. A transition caused by `skip()` hard-snaps instead, preserving
  "no simulation in skipped class time";
- BREAK/DAYEND/IDLE: `set_ai_enabled(false)`, cancelling travel.

`Game._ready()` still spawns and wires NPCs before `start_day()`, so the initial
`PERIOD1` starts a class walk from the spawn point. A forced travel deadline
(`travel_timeout_sec`, default 8 s) guarantees arrival long before the
end-of-class attendance check. `Npc.resume_saved_goal()` restores a saved
`class:` goal on load.

## Acceptance mapping

| Checkbox | Covered by |
|----------|------------|
| Goal from interests + mood | `NpcAi.select_goal()` weighted selection |
| Movement via `NavigationAgent2D` | `Npc.gd` agent + `MapRenderer`'s nav region |
| Re-evaluate on period change / completion | `Game._on_state_changed()` + arrival handling |
| Smooth, obstacle-avoiding movement | nav path following + physics `move_and_slide()` |
| No stuck NPCs | timeout + straight-line fallback + re-evaluation |

"Goal from relationship meters" is explicitly deferred to 014/015 per the recorded
decision.

## Verification plan

Headless Godot scripts assert: hangout markers/tags resolve, interest+mood weighting
is deterministic for a fixed seed, goal selection returns a destination inside the
map, all four NPCs accumulate travel without getting stuck over 10 s, AI disables and
goals clear on class entry, goals re-evaluate on every free-time entry,
`goal_destination` round-trips through the instance snapshot, per-template interest
distributions differ, a zero-speed NPC with a usable path re-evaluates its goal,
BREAK disables/resumes AI, and a DebugStart → Game.tscn launch has no parse/runtime
errors. Class-travel verification adds: walking from spawn at day start, walking
on class entry when the lead window was missed, lead-based departure at free-time
end, hard-snap on skip, all NPCs seated within 10 s, BREAK cancellation, and
saved `class:` goal resume, and a skip out of class followed by a normal class
transition that still walks. Result: 33 checks, 0 failures.
