# Project Renai v1 — Brainstorming Decisions

Companion to `doc/idea-v1.md` (spec) and `doc/idea-v1-brainstorming.md` (design).
Records the clarification decisions made during the brainstorming session.

## Decisions

### Scope
- **Middle path:** load-bearing foundations + core loop vertical slice. Surface features (menus, creation tools, mod UI, calendar/break screens) deferred. v1 is a single-day test.

### Approach
- **Approach A — Data-first vertical slice.** Schemas/registries first, then ModLoader + SaveManager, then one playable day. (Approach B full-scaffold and C throwaway-spike rejected.)

### NPC Data Model
- **Template + instance.** CharacterTemplate (authored, shared, immutable at runtime) + NpcInstance/PlayerInstance (per-save runtime state: stats deltas, mood, meters, position, schedule progress, goal). Both player and NPCs use the same character base across saves. Instance references template by stable template ID.

### Movement & Maps
- **Free 2D movement on a tile-based grid.** Collision via Godot physics. Maps are `.tres` resources (tile data + placed objects + spawn + navmesh), edited by an in-game drag-and-drop editor. Renderer builds the world from data.

### Day Structure
- **Explicit state machine:** Period1 → FreeTime1 → Period2 → FreeTime2 → Period3 → FreeTime3 → Period4 → DayEnd → Save → NextDay. In-school free time between periods = free roam for the player. Weekend/season breaks = choice pop-up (deferred, non-goal for v1).

### NPC AI (free time)
- **Goal-driven light AI** based on traits, interests, and relationship levels (seek friends/love interests, avoid enemies). Goals → destinations; movement via NavigationAgent2D on baked navmesh. Re-evaluate on period change or goal completion.

### Dialogue
- **Data-driven `.tres` topics** with conditions (mood/interest/trait/familiarity thresholds, required stat) and effects (affection/familiarity/mood deltas for success/failure). Pool of 3–5 filtered at runtime. Moddable by dropping resources.

### Interaction Resolution
- **Threshold check:** `stat + (familiarity/10) + random(0..5) >= difficulty` (difficulty per topic, may incorporate recipient stats/traits). Margin scales affection delta severity.

### Relationship Meters
- **Topic-defined deltas** (affection + familiarity, success/failure variants), with severity varying by interaction with receiver's traits and stats.
- Meters: Familiarity 0–100, Affection −100..100. Types: Stranger (Fam<20), Friend (Fam>=20 & Aff>=20), Enemy (Aff<=-20), Lover (Fam>=60 & Aff>=60 & mutual orientation/gender).

### Saves
- **Godot Resource saves** (`.tres`/`.res`), file-based, unlimited slots, `user://`. Instances link to templates via stable template IDs. Autosave + manual. No day-end summary screen.

### Mod Loader
- **Scan + manifest with dependencies.** Scan `res://mods/`; each mod folder needs `mod.json` (name, version, author, entry script, dependencies list, content list). Validate manifest, entry, and dependencies at startup (topological order, cycle detection). Enable/disable flags. **Add-only** for v1 (no override). On failure, log and skip (no crash).

### Stats & Growth
- Stats: STR, DEX, CON, INT, WIS, CHA (gate dialogue + affect success). Traits set starting stats + modify growth rates. Growth via break activities + interactions (traits modify rate). Pipeline must exist even in single-day v1.

### Mood
- Numeric 0–100, clamped. Affects dialogue eligibility and lightly affects stat checks. Updated by interaction outcomes.

### Camera & UI
- Camera: follow player with smoothing. Minimap for navigation. UI simple but cute. Relationship meter change shown after interaction (toggle, default on).

### Audio & Localization
- Music + SFX (volume in Options). English only (v1); framework ready.

### Stated implementation calls (builder may refine)
- Pathfinding: NavigationAgent2D with baked navmesh per map (steering fallback if baking is slow).
- Interaction trigger: Area2D proximity + E keypress via InteractionComponent.
- Time: real-time clock in TimeManager driving the state machine; skip advances to next period boundary.
- Camera smoothing params, goal-selection algorithm, save versioning, dependency resolution algorithm details: left to builder.

### Brainstorming Q&A (builder check)

**Q1 — Launch & entry point (v1):** A. Debug launcher scene `DebugStart.tscn` auto-starts a default day; base resources authored by developer in the Godot editor (plan provides schema + checklist).

**Q2 — NPC-initiated interactions:** B. NPCs can initiate with player OR other NPCs. NPC chooses target by outgoingness + familiarity when not already pursuing a goal; then receives the same filtered dialogue pool as a player and picks one option at random. Pipeline is pair-agnostic `(initiator_id, target_id)`.

**Q3 — Per-period class locations:** A. Per-instance schedule referencing named map markers. Attendance simulated for NPCs (perfect in v1 — their only goal is to attend; no repercussions).

**Q4 — Relationship meter storage:** A. Per-instance directed dictionaries (`meters: { other_id → {familiarity, affection} }`).

### Minor calls (recorded for review)
- Base content packaging: base resources under `res://resources/` loaded directly; ModLoader exercised by one sample mod under `res://mods/`.
- Placed map objects: `Item` resource carries a `PackedScene` reference (plus sprite/collider) instantiated by the renderer.
- NPC attendance (v1): simulated but perfect; no repercussions.
- NPC-initiated targeting: player or NPC, gated by outgoingness + not-busy.

### to-spec decisions
- **Exposed endpoints:** Skipped (no network surface); module interfaces documented under Implementation Decisions.
- **Testing seam:** Highest seam — single integration test at the day-loop level (spawn → move → talk → save → reload) via DebugStart.tscn.
- **Issue tracker:** GitHub repo created; spec published as an issue with `ready-for-agent` label.
- **User stories depth:** Extensive — covers movement, interaction, dialogue, relationships, save/load, modding, NPC AI, attendance, mood, stats, camera, minimap.

### to-tickets decisions
- **Ticket location:** `doc/tickets/` (user-specified; overrides skill's default `.scratch/.../issues/`).
- **Ticket count:** 18 tickets, finer-grained than the initial 10-ticket proposal.
- **Granularity:** ~18 tickets accepted by user; each independently shippable and verifiable.
- **Blocking edges:** Each ticket depends only on tickets that genuinely gate it; parallelizable siblings (004/005/006, all blocked only by 001) can be built concurrently.
- **Base content authoring (007):** Separate ticket, as requested.
- **Acceptance verification (018):** Final integration ticket owns verifying all 10 acceptance criteria; each prior ticket also has its own acceptance criteria.
- **Ticket format:** one file per ticket, named `<NN>-<short-description>.md`, using the local-ticket template (What to build, Blocked by, Status, acceptance criteria checkboxes).
- **GitHub issues:** 18 issues created (#2–#19) as sub-issues of spec #1, with `ready-for-agent` label and native blocked-by edges. Issue numbers map 001→#2 … 018→#19.

### Chunk loading (planned, post-v1 optimization)
- **Plan D (hybrid) chosen.** Close tier: full sim + full render. Near tier: full NPC state, reduced tick rate, objects hidden, simplified collision. Far tier: identity preserved, tick rarely with large dt, coarse position, no render, coarse pathfinding.

### Ticket 002 — Autoload skeleton (implementation decisions)
- **Language:** GDScript for all six stubs (not C#). Keeps the change minimal and avoids C# toolchain/setup; later tickets may migrate individual autoloads to C# where data-heavy, updating the autoload path in `project.godot`.
- **Location:** `res://scripts/<Name>.gd` (flat, no autoloads subfolder).
- **Registration:** `[autoload]` section in `project.godot` with the `*` prefix (e.g. `GameManager="*res://scripts/GameManager.gd"`), verified to load and expose each as a global identifier accessible from a scene.
- **No `class_name`:** Autoload scripts deliberately omit `class_name`. Declaring `class_name GameManager` (matching the autoload name) raises "Class 'GameManager' hides an autoload singleton" and breaks loading. If typed references are needed later, use a distinct class name.
- **Chunk:** fixed tile grid, same size/shape across maps (map dimensions vary).
- **Center of loading:** player position, with buffer for pop-in prevention.
- **Tier distances:** chunk-radius based, configurable by player (optimization setting), with sensible defaults. Close radius 2, near radius 4, far beyond.
- **Hysteresis:** promote at inner radius, demote at outer radius + 1 chunk buffer. Promotion interpolates position over ~0.5s.
- **Far-NPC fidelity:** keep full identity/state (no zone abstraction); tick every ~5–10s with large dt; coarse (straight-line) pathfinding.
- **Interaction guard:** only close-tier NPCs interactable; attempting to interact with a near NPC promotes it first (safety net for tier-update lag, small close radius, NPC-initiated, zoomed-out camera).
- **Memory:** all NPC state in memory (v1); disk streaming deferred.
- **Save/load:** store all NPC state; tiers recomputed from player spawn position on load.
- **Scale target:** future very-large maps + 100s of NPCs (after-school activities); rates tunable then.
- **Config:** tier radii and tick rates as settings (Options UI wiring deferred; config-level support in ChunkManager).
- **Map editor:** chunks auto-derived from map dimensions + chunk size; editor shows chunk grid overlay.

### Ticket 003 — DebugStart launcher (implementation decisions)
- **Game.tscn handling:** A minimal placeholder `scenes/Game.tscn` (Node2D root) is created now so DebugStart can load it without errors; later tickets (map renderer, movement, etc.) populate it.
- **Fresh-start path:** GameManager owns the fresh-start (no save) path. `start_fresh_day()` sets `current_save = null` and defers `change_scene("res://scenes/Game.tscn")`. The scene change is deferred (`call_deferred`) so it is safe to invoke from `_ready()` without triggering "parent node is busy" errors.
- **Entry point:** `run/main_scene` in `project.godot` points to `res://scenes/DebugStart.tscn`, so the project launches straight into the debug launcher with no menu flow.
- **DebugStart scene:** `scenes/DebugStart.tscn` (Node root) with `scripts/DebugStart.gd`, which delegates to `GameManager.start_fresh_day()` rather than switching scenes itself.
- **Autoloads:** remain stubs; none assume a save exists, so a fresh start does not crash. `GameManager.current_save == null` denotes "no save / fresh start".

### Ticket 006 — DialogueTopic schema (implementation decisions)
- **File:** `res://scripts/DialogueTopic.gd`, `class_name DialogueTopic extends Resource`.
- **Identity fields:** `id: String`, `text: String`.
- **Condition fields (eligibility):** `min_mood: int` (0 = no gate), `min_familiarity: int` (0 = no gate), `min_affection: int` (0 = no gate), `required_interests: PackedStringArray`, `required_traits: PackedStringArray`, `required_stat: String` (stat name; empty = none), `required_stat_min: int` (ignored when `required_stat` is empty). All conditions must pass for eligibility.
- **Resolution fields:** `checked_stat: String` (stat used in `stat + (familiarity/10) + random(0..5) >= difficulty`; empty = no stat bonus), `difficulty: int`.
- **Deltas:** separate success/failure variants for affection, familiarity, and mood — `affection_delta_success/failure`, `familiarity_delta_success/failure`, `mood_delta_success/failure` (all `int`). All deltas are applied to both parties' directed meters by the resolution ticket (015).
- **Types:** free-form strings for stat/interest/trait ids (consistent with CharacterTemplate/Trait), matching the modding convention; meters are integers so deltas are ints.
- **Margin scaling:** handled by the resolution step (ticket 015), not the schema.
- **Verification:** `DialogueTopic.new()` instantiates and `ResourceSaver.save` + `ResourceLoader.load` round-trips all fields; registered in the global script class cache so it appears in the editor's "New Resource" dialog.

### Ticket 008 — Map renderer (implementation decisions)
- **File:** `res://scripts/MapRenderer.gd`, `class_name MapRenderer extends Node2D`.
- **Entry point:** exported `map: Map`; `render(map)` builds (or rebuilds) the world and is also called from `_ready()` when `map` is assigned. `Game.tscn` now contains a `MapRenderer` child wired to `map_school.tres`.
- **Tilemap:** a `TileMap` named "TileMap". Uses `map.tile_set` when provided; otherwise generates a fallback `TileSet` (one grey tile, `tile_size` from map) so maps without an authored tileset still render. Cells set from flat row-major `tile_ids` (-1 clears).
- **Placed objects:** a `Node2D` named "PlacedObjects" with one child per `placed_objects` entry, instantiated from `item.packed_scene` (or a bare `Node2D` when missing). Position taken from the entry's `position`. Sprite/collider data from `Item` is applied (Sprite2D from `sprite` or a type-colored placeholder; StaticBody2D + CollisionShape2D when `blocks_movement`, using `collider_shape` or a default rectangle).
- **Navigation:** a `NavigationRegion2D` named "NavigationRegion2D" with `navigation_polygon = map.navigation_mesh`.
- **Spawn point:** exposed as `spawn_point: Vector2` and `get_spawn_point()`, plus a `Marker2D` named "SpawnPoint" at that position.
- **Empty maps:** renders tilemap + (empty) PlacedObjects + nav region + spawn marker without errors.

### Ticket 005 — Item + Map schemas (implementation decisions)
- **Item fields:** `id`, `type`, `packed_scene: PackedScene`, sprite data (`sprite`, `sprite_offset`, `sprite_scale`), collider data (`collider_shape`, `collider_offset`), and furniture/wall properties (`blocks_movement`, `blocks_sight`, `interactable`, plus free-form `properties: Dictionary`).
- **Map tile data:** `width`, `height`, `tile_size`, optional `tile_set`, and a flat row-major `tile_ids: PackedInt32Array` (-1 = empty).
- **Placed objects:** `placed_objects: Array` of dictionaries `{ "position": Vector2, "item": Item }`, instantiated by the renderer from each item's `packed_scene`.
- **Spawn point:** `spawn_point: Vector2` (world space).
- **Navigation mesh:** `navigation_mesh: NavigationPolygon`.
- **Chunk seams:** `chunk_size: int = 32`; derived read-only `chunk_grid_width`, `chunk_grid_height`, `chunk_grid_size` (ceil division, 0 when size <= 0 or dimension <= 0).
- **Map identity:** `id`, `display_name` for registry/mod linkage.

### Ticket 009 — Free 2D movement + collision + camera + minimap (implementation decisions)
- **Player controller:** `scripts/Player.gd`, `class_name Player extends CharacterBody2D`. Circular collider (radius 6), `move_and_slide()` in `_physics_process`, velocity steered with `move_toward` toward `Input.get_vector("move_left", "move_right", "move_up", "move_down")` × `speed` for smooth analog response. Player spawns at the MapRenderer's `get_spawn_point()` via a deferred lookup in `_ready()` (survives sibling ready-order). Player is in group `player` for the future InteractionComponent. Visual is a generated `_draw()` circle (no art assets in v1).
- **Input:** four actions (`move_left`, `move_right`, `move_up`, `move_down`) defined in `project.godot` `[input]`, each with WASD + arrow keys (digital) and gamepad left-stick/d-pad events (analog). `Input.get_vector` normalizes diagonals and supports gamepad sticks. A defensive runtime `InputMap` registration in `Player._ready()` fills in any action missing from ProjectSettings.
- **Collision:** reuse the `StaticBody2D` + `CollisionShape2D` nodes MapRenderer already creates for items with `blocks_movement` (all three base items set it). Player uses default collision layer/mask 1; no new physics layers. A straight-line physics move is sufficient; no tile-by-tile snapping.
- **Camera (user-approved):** `scripts/FollowCamera.gd`, `class_name FollowCamera extends Camera2D`. The camera is a **child of Player** in `Game.tscn`, so it inherits the player transform and Camera2D's built-in `position_smoothing_enabled` / `position_smoothing_speed` (~10) supplies the follow lag. Do **not** write `global_position` from a script every frame while smoothing is enabled. Exported `zoom_level` originally defaulted to **8** (zoom in) for the tiny 160×128 map; it is now **4** (user-approved final value) so more of the larger map is visible while follow stays observable. Tunable in-editor; the scene value in `Game.tscn` overrides the script default, so both are set to 4.
- **Camera limits — corrected after user-visual testing:** limits are the map's **raw pixel bounds** (`0 .. width*tile_size`, `0 .. height*tile_size`), `limit_smoothed = true`, recomputed on map swap. An earlier "view-aware" inset (subtracting half the zoomed viewport) was wrong: Godot already accounts for viewport and zoom when clamping, so the inset collapsed the limit range to 16 px and made the camera drift **opposite** to the player at a real 1152×648 viewport. Regression check at that viewport: world-space screen center moves `69.5 → 79.2` as the player moves `56 → 86.7`, and caps at `88.0` (no view past the map edge). Original 64×64 headless viewport hid the bug; subsequent verification uses a realistic viewport size.
- **Camera jitter fix (user-reported blur):** Camera2D built-in position smoothing was **disabled**; smoothing is now done manually in `FollowCamera._physics_process` with `1 - exp(-speed * delta)` and applied as the camera's local offset (`smooth_world - player_world`). The player moves in physics ticks too, so both update in lockstep; previously the camera interpolated every render frame while the player stepped, producing a ~14 px sawtooth (visible blur/oscillation at 8× zoom). Measured: steady-state player-to-camera offset changes by at most **0.29 px** after convergence. Enabling `physics/common/physics_interpolation` was tested and did not remove the headless sawtooth, so it was not kept.
- **Minimap (user-approved):** `scripts/Minimap.gd`, `class_name Minimap extends Control`, drawn data-first via `_draw()` — not a second viewport. Reads `Map.tile_ids` for floor squares, `placed_objects` with `item.blocks_movement` for wall/furniture blocks, and the player's `global_position` for a dot; uniformly scaled to fit a fixed top-right panel. `queue_redraw()` only when the player moves past a small threshold or the map changes, keeping cost negligible at 60 fps. NPC dots can be added later by reading NPC positions, with no scene/viewport changes.
- **Scene wiring:** `Game.tscn` gains `Player` (with CircleShape2D), `FollowCamera`, and `MinimapLayer`/`Minimap`; exported `NodePath`s wire camera/minimap to Player and MapRenderer. MapRenderer needed no changes.
- **Spawn-point fix (discovered during verification):** the authored spawn `(24, 24)` sat on the corner of the desk collider at `(32, 32)` (rect x 24–40, y 24–40), so the radius-6 player was pushed to `x≈18` on load and immediately blocked from moving right. `map_school.tres` `spawn_point` was moved to **`(56, 24)`**, an open tile inside the navmesh. No other map data changed.
- **Verification:** headless Godot 4.2.1 script asserts player moves on input, is blocked by a wall/desk, camera follows with correct zoom/limits, minimap draws without errors, and the default map loads with no parse/runtime errors; plus a user-visual check of motion smoothness.

### Ticket 010 — ModLoader (implementation decisions)
- **Registry ownership:** `ModLoader` (autoload) owns the ID→resource registries; no new autoload is added. Registries are typed buckets keyed by resource class (`character`, `trait`, `item`, `map`, `dialogue`) mapping stable `id` → `Resource`, exposed via `register_resource()`, `get_resource()`, `has_resource()`, `get_all()`, and `get_registry()`. This follows the spec (§5.2/§5.4: "ModLoader maintains an ID→resource registry") and avoids `project.godot` churn.
- **Type detection:** a content resource is bucketed by its class (`CharacterTemplate`, `Trait`, `Item`, `Map`, `DialogueTopic` via `is` checks); unsupported classes or empty `id` are logged and skipped.
- **Mod id:** the `id` field in `mod.json` when present and non-empty; otherwise the folder name. Dependencies reference these ids. Duplicate ids are logged and the later mod is skipped.
- **Manifest contract:** required fields `name`, `version`, `author` (non-empty strings), `entry` (non-empty script path), `dependencies` (array of strings), `content` (array of resource paths). Optional `id` (string) and `enabled` (bool, default `true`). Missing/wrong-typed required fields cause a logged skip.
- **Enable/disable:** a mod is disabled when `enabled` is `false` in `mod.json` or when a `.disabled` marker file exists in its folder. v1 has no Mods Menu, so the flag is file-based (spec §5.5). Disabled mods are skipped and do not count as satisfied dependencies.
- **Entry script contract:** `entry` must point to a loadable GDScript that instantiates (v1 convention: `extends RefCounted`). After the mod's `content` resources are loaded and registered, ModLoader instantiates the script and calls `register(loader)` if that method exists, for mod-specific setup. A missing/unloadable/instantiation-failing entry causes the mod to be skipped with a log, no crash.
- **Content loading:** every path in `content` is loaded with `ResourceLoader` and auto-registered by type/id; a single unloadable content resource is logged and skipped without failing the whole mod.
- **Dependency resolution:** Kahn topological sort over the discovered mod ids; mods left unprocessed after the sort form or depend on a dependency cycle and are logged and rejected. A dependency that is missing, invalid, disabled, or skipped causes the dependent mod to be skipped with a clear log.
- **Add-only:** registering an id that already exists is logged and rejected (no override), per the v1 non-goal.
- **Testability seam:** `load_mods(root_path := "res://mods/")` is public and re-runnable (clears state first), so headless tests can point it at a synthetic mod tree under `user://` to exercise failure paths without touching real content.
- **Re-entrancy guard:** `load_mods()` ignores re-entrant calls while a load is in progress. Entry hooks receive the loader as `register(loader)`, so without the guard a mod could clear registries mid-load and cause false "missing dependency" skips for later mods.
- **Diagnostics schema:** `get_last_report()` entries are `{ mod, status, reason, folder }`. Discovery-stage skips key `mod` by folder name (the fallback id); duplicate-id skips use a composite `id@folder` key so they cannot collide with the surviving mod's `loaded` entry. Cycle diagnostics phrase the reason as "member or dependent" because Kahn's leftover set includes both cycle members and their dependents.

### Ticket 011 — Day state machine (implementation decisions)
- **Approach A — state machine inside TimeManager (chosen).** Matches the spec ("TimeManager — day clock … drives the day state machine"), one file, simplest seam. A separate `DayStateMachine` class and Timer nodes per phase were rejected (no v1 consumer / drift + scene wiring).
- **Clock:** `_process(delta)` calls public `advance(delta)`, which accumulates real-time seconds and transitions when the phase duration is reached. Durations are exported/tunable (defaults 45 s class, 30 s free time, ~1 s for DayEnd/Save/NextDay). `advance()` is the deterministic headless-test seam; no wall-clock/calendar in v1.
- **Single transition point:** `_enter_state(next)` emits `state_changed`; leaving a `PERIODx` calls `_record_period(period)`. Natural completion and `skip()` share this path so a skipped class is still recorded (user-confirmed: "count every period").
- **Skip semantics (with user-approved seam):** `skip()` emits `skip_simulation_requested(from_state, to_state, skipped_duration)` and holds a short, configurable pause beat (`skip_pause_sec`, default ~0.5 s, clock halted) before force-completing the current phase (firing period-change logic if it is a class) and entering the next state with elapsed reset. "No simulation in skipped class time" means no intermediate ticks/AI/movement — the signal + beat are a hook for tickets 013/016 and the deferred loading UI to run fast-forward later, not simulation implemented in 011. Re-entrant skips while a beat is pending are ignored.
- **Attendance + grade data model:** self-contained records in `TimeManager` keyed by period then character id (user-confirmed). No `NpcInstance`/`PlayerInstance` introduced in 011 (those are 012+). NPC attendance is perfect (always `true`). Roster is settable via `set_roster()`; default falls back to `ModLoader` character ids so NPC attendance is observable without hard-coded ids. **Ticket 012 must pass stable instance ids (not template ids) to `set_roster()`** — records are keyed by id and duplicate ids collapse.
- **Stats provider seam:** a `Callable` set via `set_stats_provider()` returns `{intelligence, wisdom}` per character id; default reads `CharacterTemplate` INT/WIS from the ModLoader registry (player maps via `player_template_id`). Because base characters live in `res://resources/` and are not in the ModLoader registry, the player also has an exported `player_template_path` (default `res://resources/characters/char_alex.tres`) loaded directly as a fallback. Later tickets inject instance-backed stats. `_player_id` is initialized from the exported `player_character_id` in `_ready()`; `set_roster()` is the explicit override.
- **Grade stub formula:** when present, `score = clampi(60 + (int+wis)/2, 0, 100)`, `bonus = clampi(1 + (int+wis)/20, 0, 3)` (both 0 when absent); letter is derived from score. Constants exported/tunable. `get_stat_bonuses()` returns per-id sums across periods for tickets 015/018 to apply.
- **DayEnd save seam (user-confirmed):** TimeManager emits `day_ended` + `manual_save_requested("day_end")` and calls a guarded `SaveManager.autosave(snapshot)` hook. `TimeManager.get_day_snapshot()` / `restore_day_snapshot()` expose day, state, elapsed, attendance, grades, roster, player id and absence flag so ticket 017 can persist and resume a day; `SaveManager.gd` gains a log-only `autosave(snapshot)` stub now. No save logic duplicated in 011, no day-end summary screen.
- **Break days:** `BREAK` is a separate enum state with `start_break_day()`/`end_break_day()` and a `break_day_started` signal; deliberately outside the normal sequence and not exercised in v1.
- **Day loop:** after `SAVE`, `NEXTDAY` increments the day counter, clears the per-day records, and re-enters `PERIOD1`, so the sequence is repeatable. `day_started` is emitted on `PERIOD1` entry for both fresh starts and rollovers. Fresh-start wiring: `GameManager.start_fresh_day()` only clears the save and switches to `Game.tscn`; the new `Game.gd` root script calls `TimeManager.start_day(1)` in its own `_ready()` so scene-level listeners are connected first. Entering `BREAK` records an interrupted class and resumes at the following phase on exit.

### Ticket 012 — NPC spawning & scheduling (implementation decisions)
- **Base templates registered into the ModLoader registry (user-approved).** `load_mods()` registers all `res://resources/characters/*.tres` base `CharacterTemplate`s first (bucket `character`, owner `"base"`), then mod content. This makes the ticket's "spawn via the ModLoader registry" literal: the spawner resolves template IDs only through `ModLoader.get_resource()`. Base registration is re-run on every `load_mods()` so re-scans (e.g. headless tests) restore it; a mod ID colliding with a base ID is rejected add-only, so mods cannot silently override base templates.
- **Named class markers live on the `Map` resource (user-approved).** Added `@export var markers: Dictionary` mapping a stable marker name (e.g. `"classroom_a"`) to a world-space `Vector2`, authored in `map_school.tres`. `Map.get_marker(name)`, `has_marker(name)` and `get_marker_names()` are the read API; schedules store marker *names*, not positions, so moving a marker updates every NPC.
- **Period transitions reposition NPCs instantly (user-approved in 012, SUPERSEDED).** Originally each NPC's `position` and node `global_position` were set directly to its scheduled marker on class entry. **Overturned by the user after ticket 013:** now that `NavigationAgent2D` exists, NPCs walk to class; see the "Ticket 013 — class travel" section below. The hard-snap fallback remains for skipped transitions.
- **Instance shape: a single `NpcInstance` Resource (user-approved).** `scripts/NpcInstance.gd` (`class_name NpcInstance extends Resource`) carries every instance field: `instance_id` (stable roster id), `template_id`, `display_name`, `stats`, `mood`, directed `meters`, per-period `schedule`, `position`, `current_goal`, and runtime-only `tier` (default `"close"`). The player will reuse this same shape in later tickets; a separate `PlayerInstance` class is not introduced in 012.
- **`tier` is runtime-only.** It is an unexported `var tier: String = "close"` with the `close`/`near`/`far` constants kept on the class for post-v1 chunk loading. Ticket 017 must exclude it from serialization (it is recomputed on load per the chunk-loading plan).
- **NPC roster uses stable instance IDs.** `Game.gd` calls `TimeManager.set_roster("player", [instance_id, ...])` with ids like `npc:0`, and installs a stats provider backed by each `NpcInstance.stats`, so attendance/grade records are per-NPC and do not collapse when two NPCs share a template.
- **Attendance stays in TimeManager's per-period records.** No attendance field is duplicated onto `NpcInstance`; `TimeManager.get_attendance()[period][instance_id]` is the authoritative record, matching the ticket 011 decision that records are self-contained and keyed by id.
- **Default schedules are deterministic.** Each NPC's period→marker schedule rotates through the map's sorted marker names by NPC index, so 4 NPCs distribute across 4 classrooms rather than stacking. A map with no markers falls back to its spawn point with a warning (no crash).
- **Missing template is recoverable.** If `ModLoader.get_resource()` returns null for a requested template ID, the spawner logs a warning, records the failure in a diagnostic array (`get_last_report()`), skips only that NPC, and continues spawning the rest — no crash, consistent with spec acceptance criterion 7.
- **Scaffold NPCs are `CharacterBody2D` nodes.** `scripts/Npc.gd` (`class_name Npc`) holds an `NpcInstance`, draws a generated coloured circle, and joins group `npc`. A collider is included now so ticket 013 can add `NavigationAgent2D` movement without changing the node type.
- **Three extra base character templates authored** (`char_jordan.tres`, `char_riley.tres`, `char_taylor.tres`) so 4 NPCs spawn from 4 distinct authored templates regardless of mod enable/disable state, without using the player's `char:alex` template. The sample mod's `char:mod_sample` stays registered as an optional extra.
- **Player template excluded from the default roster fallback (review fix):** `TimeManager._ensure_roster()` now skips `player_template_id` and the template at `player_template_path`, so registering base characters cannot create a phantom `char:alex` attendance record on paths that omit `set_roster()`.

### Ticket 013 — NPC goal-driven AI (implementation decisions)
- **Hangout destinations are named map markers (user-approved).** Dedicated `hangout_*` markers are authored in `map_school.tres`, kept distinct from the four `classroom_*` schedule markers. Free-time goals target a hangout marker name resolved through `Map.get_marker(name)`; positions can be moved in the map resource without touching AI code. Class markers remain schedule-only.
- **Interest → hangout tagging (user-approved).** `Map` gains `hangout_interests: Dictionary` mapping a hangout marker name to a `PackedStringArray` of interest ids/tags (e.g. `trait:likes_sports` and/or `sports`). Matching hangouts are weighted higher during goal selection. Preference keys come from all trait categories except `dislike` (review fix #1): the authored roster expresses preferences through `skill` and `personality` traits as well (Riley's studious → `academic`/`study`, Taylor's outgoing → `social`), so all four hangouts are reachable; an `interest`-only filter left 2 of 4 NPCs with no preferences. Mood biases the weighting: low mood favours `quiet`-tagged hangouts, high mood favours preference-matched ones.
- **Relationship-driven goals deferred (user-approved).** Seek-friends/love-interest and avoid-enemy goals are NOT implemented in 013: directed `meters` are empty until dialogue tickets 014/015 populate them. 013 implements interest + mood goals only and exposes a documented relationship-candidate hook in `NpcAi` that returns an empty set in v1, so 014/015 can add seek/avoid without restructuring. NOTE: this narrows ticket-013 checkbox #1 relative to its original wording ("interests, mood, and relationship meters"); the deferral is explicit and user-approved.
- **Seeded determinism (user-approved).** Goal selection uses a `RandomNumberGenerator` seeded by `instance_id.hash()` combined with the period and a re-evaluation counter, so re-evaluations within a period are reproducible and headless verification is stable. Global `randi()` is not used.
- **Separation of concerns (builder call).** Pure goal selection lives in `scripts/NpcAi.gd` (`RefCounted`), taking an `NpcInstance`, its resolved `CharacterTemplate`, a `Map`, and the period, and returning a goal string plus destination. `scripts/Npc.gd` owns the `NavigationAgent2D` and physics-tick movement. `Game.gd` enables AI on `FREETIME*` entry and disables/clears it on class entry (relying on 012's instant repositioning).
- **Goal representation (builder call).** `NpcInstance.current_goal` holds a structured string (`"hangout:<marker_name>"`, empty when idle). A new exported `goal_destination: Vector2` on `NpcInstance` stores the chosen destination and is included in `snapshot()`/`from_snapshot()` so ticket 017 can restore in-flight goals.
- **Stall / stuck handling (builder call).** Each movement attempt has a timeout. If the nav path is empty/unreachable or the NPC makes no progress, it falls back to straight-line steering toward the destination, then re-evaluates the goal rather than freezing. The no-progress flag is persistent (`_force_fallback`) because a merely "usable" nav path must not erase a detected stall (review fix #2). Verification found that the hand-authored `map_school.tres` navmesh `polygons` overlap the bench/desk physics colliders (the `outlines` hole is re-bake source data only), so straight-line steering pinned two NPCs against the bench; `Npc.gd` also detects slide collisions and steers along the collider tangent (goal-aligned) for a short beat before resuming the nav path. Re-baking the navmesh against furniture is a follow-up data task, not required for v1.
- **Ticket 016 seam (builder call).** `Npc` exposes `is_busy()` (true while pursuing a goal); NPC-initiated interaction targeting uses it as the "not-busy" gate. 013 does not implement initiation or dialogue.
- **Non-free-time states stop AI (review fix #4).** `Game._on_state_changed()` disables AI for every state that is not `FREETIME*`, including BREAK, DAYEND and IDLE — a `period <= 0` early return would otherwise leave NPCs moving while the clock is paused.
- **Review follow-ups left open:** ticket-017 restore must explicitly re-enable AI (no `state_changed` fires on `restore_day_snapshot()`) and apply `goal_destination` to the nav agent; `_is_free_time_state()` should use the signal's state argument; `NpcAi.relationship_candidates()` is defined but not yet wired into selection (tickets 014/015). These are recorded in `doc/code-review/codereview-ticket-013-npc-goal-driven-ai.md` findings 3, 5 and 6.

### Ticket 013 — class travel (user-approved change; supersedes 012 instant reposition)
- **NPCs walk to class instead of teleporting (user-approved).** After the pathfinding from ticket 013, the user overturned the 012 decision that class transitions hard-snap NPCs to their markers. NPCs may now be late to attendance in principle; they are given enough lead time to arrive before the end-of-class attendance check. The lead/timeout defaults were raised (8 s / 14 s) for the larger debug map's longer walks.
- **Departure timing (builder call).** `Game.gd` checks the remaining free-time duration each frame and, when `class_travel_lead_sec` (default 4 s) or less remains, points each NPC's existing `NavigationAgent2D` at its scheduled class marker with a forced `class:<marker>` goal. No new `TimeManager` states were added, so ticket 011's approved day sequence and persisted state enum are unchanged. An alternative — inserting short TRAVEL phases before each class — was rejected as more invasive for the same result.
- **Skip still hard-snaps (user-confirmed contract).** `TimeManager.skip()` emits `skip_simulation_requested`, which `Game.gd` records; the following class transition calls `set_ai_enabled(false)` + `move_to(marker)` instead of simulating the walk, preserving "no simulation in skipped class time".
- **Arrival guarantees (builder call).** Forced travel reuses the 013 navigation/obstacle-sliding/stall-recovery path but adds a hard `travel_timeout_sec` (default 14 s; raised from 8 s for the larger debug map) so an oscillating path cannot leave an NPC wandering; on expiry (or on stall/arrival) the body snaps exactly onto the marker and stops. Travel can be cancelled by BREAK/DAYEND and resumed from a save via `Npc.resume_saved_goal()` (a `class:` goal in `NpcInstance.current_goal` is restored into forced mode by `setup()`).

### Larger debug map (user-approved)
- **Replacement debug map (user-approved).** `resources/maps/map_school.tres` is now a **32×24 tile / 512×384 px** map (`map:school_debug_large`), replacing the 10×8 / 160×128 map so classroom and hangout markers are visibly separated (opposite classrooms ~417 px apart vs. ~60 px before). The original is preserved as `resources/maps/map_school_small.tres`; `Game.tscn` still points at `map_school.tres`.
- **Layout (builder call).** Classrooms at the four corners; hangouts at top-centre, bottom-centre, left-centre and right-centre; spawn at (256,192). Ten desk/bench obstacles form navmesh holes. The navmesh is a shared-vertex quad grid (713 vertices, 650 convex quads) authored directly — `NavigationPolygon.bake()` hangs in headless Godot 4.2.1, so no runtime baking is used.
- **Zoom changed to 4× (user-approved; final).** `FollowCamera.zoom_level` was reduced from 8 to 4 in both `scripts/FollowCamera.gd` and `scenes/Game.tscn` so multiple landmarks are visible at once on the larger map.
- **Travel timing (builder call).** `class_travel_lead_sec` 4→8 s and `travel_timeout_sec` 8→14 s accommodate walks of up to ~9 s on the larger map.
- **Navmesh authoring note for future maps (user-approved: keep as-is for this debug map).** The hand-authored quad grid is valid pathfinding data — `NavigationServer2D` only reads `vertices`/`polygons`, so how they were produced is invisible to it — and all NPC paths verified on it. For larger or more complete maps, prefer baking a `NavigationPolygon` from source outlines: it yields far fewer polygons, a much smaller `.tres`, accurate arbitrary-shaped holes around colliders, and can be re-baked in the editor when geometry changes; it also gives more direct paths (a grid can stair-step, and `NavigationAgent2D` does not smooth paths in 4.2). Caveat: `NavigationPolygon.bake()` hung in a headless 4.2.1 probe, so bake through the editor GUI (or a region attached to a live scene tree), then re-run the NPC path verification after regenerating. Do not switch this debug map: it is verified and debug-only.

### Deferred (non-goals for v1)
- Main/New Game/Load/Create/Mods/Options menus (functional).
- Character/map creation tools and map editor.
- Weekend/season break choice pop-ups.
- Full academics (basic grade-per-class stub only).
- Additional languages, audio polish.
- Performance tuning beyond ~5 NPCs.
- NPC override of existing resources by ID.