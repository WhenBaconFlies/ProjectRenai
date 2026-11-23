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
- **Camera (user-approved):** `scripts/FollowCamera.gd`, `class_name FollowCamera extends Camera2D`. The camera is a **child of Player** in `Game.tscn`, so it inherits the player transform and Camera2D's built-in `position_smoothing_enabled` / `position_smoothing_speed` (~10) supplies the follow lag. Do **not** write `global_position` from a script every frame while smoothing is enabled. Exported `zoom_level` defaults to **8** (zoom in) so follow is observable on the tiny 160×128 default map and the minimap is useful; tunable in-editor.
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

### Deferred (non-goals for v1)
- Main/New Game/Load/Create/Mods/Options menus (functional).
- Character/map creation tools and map editor.
- Weekend/season break choice pop-ups.
- Full academics (basic grade-per-class stub only).
- Additional languages, audio polish.
- Performance tuning beyond ~5 NPCs.
- NPC override of existing resources by ID.