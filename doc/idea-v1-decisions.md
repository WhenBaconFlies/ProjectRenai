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

### Ticket 005 — Item + Map schemas (implementation decisions)
- **Item fields:** `id`, `type`, `packed_scene: PackedScene`, sprite data (`sprite`, `sprite_offset`, `sprite_scale`), collider data (`collider_shape`, `collider_offset`), and furniture/wall properties (`blocks_movement`, `blocks_sight`, `interactable`, plus free-form `properties: Dictionary`).
- **Map tile data:** `width`, `height`, `tile_size`, optional `tile_set`, and a flat row-major `tile_ids: PackedInt32Array` (-1 = empty).
- **Placed objects:** `placed_objects: Array` of dictionaries `{ "position": Vector2, "item": Item }`, instantiated by the renderer from each item's `packed_scene`.
- **Spawn point:** `spawn_point: Vector2` (world space).
- **Navigation mesh:** `navigation_mesh: NavigationPolygon`.
- **Chunk seams:** `chunk_size: int = 32`; derived read-only `chunk_grid_width`, `chunk_grid_height`, `chunk_grid_size` (ceil division, 0 when size <= 0 or dimension <= 0).
- **Map identity:** `id`, `display_name` for registry/mod linkage.

### Deferred (non-goals for v1)
- Main/New Game/Load/Create/Mods/Options menus (functional).
- Character/map creation tools and map editor.
- Weekend/season break choice pop-ups.
- Full academics (basic grade-per-class stub only).
- Additional languages, audio polish.
- Performance tuning beyond ~5 NPCs.
- NPC override of existing resources by ID.