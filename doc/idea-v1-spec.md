# Project Renai v1 — Spec

Companion to `doc/idea-v1.md` (spec), `doc/idea-v1-brainstorming.md` (design), `doc/idea-v1-decisions.md` (decisions).
Strategy: **Approach A — data-first vertical slice** (foundations + core loop; surface features deferred).

## Problem Statement

A developer wants to build a modular, data-driven school-life simulation in Godot 4.2 where romance and interacting character traits are the heart of the experience. The defining requirement is **modularity**: characters, maps, dialogue, traits, and items must be files (`.tres`) that can be dragged into another project or dropped into a `mods/` folder and registered automatically, with no code changes.

Today there is no code at all — the project is a blank Godot 4.2 workspace. v1 must deliver the smallest playable slice that proves the data model, modularity, persistence, and the core interaction loop end-to-end, so that later slices can add features (menus, creation tools, calendar screens) on stable seams without rework.

## Solution

Build v1 as a **data-first vertical slice**:

1. Define the resource schemas (CharacterTemplate, NpcInstance/PlayerInstance, Map, DialogueTopic, Trait, Item) and the registries that hold them.
2. Build the ModLoader (scan `res://mods/`, validate `mod.json`, resolve dependencies, register resources) and SaveManager (Godot Resource saves, template↔instance linkage via stable IDs).
3. Build the core loop: a debug launcher auto-starts a default day (default map + player + 3–5 NPCs); free 2D movement on a tile grid; in-school free time with goal-driven NPC AI; talk interactions via a pair-agnostic dialogue pipeline; an explicit day state machine (4 periods + free time + day end + save); save/reload that restores instance state identically.
4. Surface features (menus, creation tools, mod UI, calendar/break screens) are deferred; only the seams and stubs they need are established.

NPCs can initiate interactions with the player or other NPCs; the dialogue pipeline is pair-agnostic. Attendance is simulated for NPCs (perfect in v1). Relationship meters are stored per-instance as directed dictionaries.

## User Stories

1. As a developer, I want characters to be `.tres` resource files, so that I can author or mod a character by dropping a file with no code changes.
2. As a developer, I want maps to be `.tres` resource files edited by an in-game drag-and-drop editor, so that school layouts are data-driven and shareable.
3. As a developer, I want dialogue topics to be `.tres` resources with conditions and effects, so that new conversations can be added by modders.
4. As a developer, I want traits to be `.tres` resources with point costs and stat modifiers, so that the trait system is extensible.
5. As a developer, I want items (furniture, walls) to be `.tres` resources carrying a `PackedScene`, so that placed objects instantiate consistently.
6. As a player, I want to move freely around the school in 2D on a tile grid, so that exploration feels open.
7. As a player, I want the camera to follow my character with smoothing, so that navigation is comfortable.
8. As a player, I want a minimap, so that I can orient myself in the school.
9. As a player, I want to press E near an NPC to start a conversation, so that interactions are intuitive.
10. As a player, I want to choose from a small randomized pool of dialogue topics, so that conversations vary and feel natural.
11. As a player, I want dialogue success to depend on my stats and familiarity, so that my build matters.
12. As a player, I want to see relationship meters change after an interaction, so that I get feedback.
13. As a player, I want NPCs to have their own stats, traits, moods, and schedules, so that the world feels alive.
14. As a player, I want NPCs to move around during free time based on their interests and relationships, so that they feel autonomous.
15. As a player, I want NPCs to sometimes start conversations with me or each other, so that the world is not purely player-driven.
16. As a player, I want my relationships to progress from stranger to friend/enemy/lover based on meters, so that romance is meaningful.
17. As a player, I want romance to be mutual (orientation and affection both matter), so that rejection is possible.
18. As a player, I want stats to gate dialogue options and affect success, so that character builds matter.
19. As a player, I want stats to grow through interactions and activities, so that my character develops over time.
20. As a player, I want the day to be divided into periods with free time between them, so that the school routine structures play.
21. As a player, I want to skip ahead to the next period, so that I am not forced to wait.
22. As a player, I want my progress saved at the end of the day, with autosave and manual saves, so that I don't lose progress.
23. As a player, I want to reload a saved day and have it restore identically, so that saves are reliable.
24. As a modder, I want to drop a mod folder with a `mod.json` into `res://mods/` and have it discovered at startup, so that modding is frictionless.
25. As a modder, I want to declare dependencies on other mods, so that my mod can build on others.
26. As a modder, I want to enable or disable mods, so that I can troubleshoot and curate.
27. As a developer, I want a debug launcher that auto-starts a default day, so that I can test without building menus first.
28. As a developer, I want missing templates on load to be a recoverable error, so that saves don't crash.
29. As a developer, I want attendance simulated for NPCs (perfect in v1), so that the grade stub has data to work with.
30. As a player, I want mood to affect which dialogue is available, so that emotional context matters.
31. As a player, I want music and sound effects, so that the game has atmosphere.
33. As a player, I want large maps to load smoothly without lag, so that after-school areas can be expansive.
34. As a player, I want distant NPCs to keep their identity and relationships even when far away, so that romance persists across the map.
35. As a player, I want to tune optimization settings (view distance, simulation detail), so that the game runs well on my hardware.
36. As a developer, I want a ChunkManager that tiers NPC simulation by distance, so that 100s of NPCs can be supported on large maps.
37. As a developer, I want chunks to be a fixed tile grid auto-derived from map dimensions, so that chunk size is consistent across maps.

## Implementation Decisions

- **Strategy:** Approach A (data-first vertical slice). Schemas and registries first, then ModLoader + SaveManager, then one playable day. Surface features deferred.
- **Modules:**
  - `GameManager` — global state, current save, scene transitions, "fresh start / no save" path exercised by DebugStart.
  - `SaveManager` — save/load, slot management, instance↔template linkage by stable ID, save versioning.
  - `TimeManager` — day clock, calendar, period tracking, drives the day state machine, skip-to-period.
  - `ModLoader` — scans `res://mods/`, validates `mod.json`, resolves dependencies (topological order, cycle detection), registers resources, enable/disable.
  - `AudioManager` — music/SFX, volume.
  - `LocalizationManager` — string tables (English v1).
  - `InteractionComponent` — proximity (Area2D) + E keypress trigger; pair-agnostic dialogue pipeline.
  - Map renderer — builds tilemap + placed objects + navmesh from a Map `.tres`.
- **Schemas (contract):**
  - `CharacterTemplate` (`.tres`): identity (id, name, gender, orientation), appearance parts (hair, eyes, mouth, skin tone, outfit), traits (skills/interests/dislikes/personality), starting stats, stat growth modifiers, trait point cost. Authored/shared; immutable at runtime.
  - `NpcInstance` / `PlayerInstance` (runtime, saved): template ID, current stats (base + deltas), mood (0–100), per-instance directed meters (`meters: { other_id → {familiarity, affection} }`), per-instance schedule (`schedule: period → named map marker`), position, current goal.
  - `Map` (`.tres`): tile data (grid of tile IDs), placed objects (list of {position, resource ref}), spawn point, navigation mesh data.
  - `DialogueTopic` (`.tres`): id, text, conditions (mood/interest/trait/familiarity thresholds, required stat), checked stat, difficulty, success/failure affection deltas, familiarity delta, mood delta.
  - `Trait` (`.tres`): id, category (skill/interest/dislike/personality), point cost, stat modifiers (starting + growth), tags.
  - `Item` (`.tres`): id, type, `PackedScene` reference, sprite/collider data, properties.
- **Template↔instance linkage:** instances store a stable template ID string (e.g., `char:student_001`); `ModLoader` maintains an ID→resource registry. Saves store IDs, not paths/UIDs. Missing template on load is a recoverable error.
- **Mod loader contract:** scan `res://mods/`; each mod folder requires `mod.json` (`name, version, author, entry, dependencies, content`). Validate manifest/entry/deps at startup; topological order + cycle detection; enable/disable flags; **add-only** in v1 (no override). On failure, log and skip (no crash).
- **Day state machine:** explicit enum states `Period1 → FreeTime1 → Period2 → FreeTime2 → Period3 → FreeTime3 → Period4 → DayEnd → Save → NextDay` (or Quit). Period change: NPCs move to class locations (from per-instance schedule referencing named map markers), attendance recorded, grade computed (attendance + INT/WIS → small stat bonus). Free time: player roams; NPCs run goal-driven AI; interaction available. Skip advances to next period boundary. Attendance simulated for NPCs (perfect in v1 — their only goal is to attend; no repercussions).
- **NPC goal-driven AI (free time):** goals chosen from traits (interests), mood, and relationship meters (seek friends/love interests, avoid enemies) → destination (hangout spot or another NPC). Movement via `NavigationAgent2D` on a baked navmesh. Goals re-evaluate on period change or completion. NPC-initiated interactions: an NPC with sufficient outgoingness may initiate with player or another NPC when not already pursuing a goal, choosing target by outgoingness + familiarity; the initiator receives the same filtered dialogue pool and picks one option at random; threshold roll and deltas apply to both parties' directed meters. Pipeline is pair-agnostic `(initiator_id, target_id)`.
- **Interaction & dialogue:** trigger via `Area2D` proximity + E (player) or NPC initiation. Pair-agnostic pipeline filters eligible `DialogueTopic` resources → random pool of 3–5. Player picks manually; NPC initiator picks at random. Resolution: threshold check `stat + (familiarity/10) + random(0..5) >= difficulty` (difficulty per topic, may incorporate recipient stats/traits). Margin scales affection delta. Effects applied to both parties' directed meters (affection, familiarity, mood). Relationship type derived from meters (Stranger/Friend/Enemy/Lover) with mutual romance gating (orientation + gender + thresholds).
- **Stats & growth:** STR, DEX, CON, INT, WIS, CHA gate dialogue options + affect success. Traits set starting stats and modify growth rates. Growth via break activities + interactions (study→INT, socialize→CHA, etc.); traits modify rate. Pipeline must exist even in single-day v1.
- **Mood:** numeric 0–100, clamped; affects dialogue eligibility and lightly affects stat checks; updated by interaction outcomes.
- **Camera:** follow player with smoothing (Camera2D); minimap as secondary view.
- **Save system:** whole game state as a Godot Resource (`.tres`/`.res`): current day, period/state, player instance, NPC instances, relationship meters, positions, mood, stats. Unlimited slots, file-based in `user://`. Autosave + manual. No day-end summary screen; save prompt only. Save version field for forward compatibility.
- **Audio & localization:** music + SFX (volume in Options; can be stubbed in v1); English only (v1), framework ready.
- **Languages:** GDScript (gameplay/UI, editor tooling) + C# (data-heavy systems, registries, save serialization); interop via Godot's bridge; keep boundary at data/registry seams, not per-frame gameplay.
- **Launch (v1):** minimal debug launcher scene `DebugStart.tscn` auto-starts a default day (default map + player + 3–5 NPCs), no menu flow. Base resources authored by developer in the Godot editor; plan provides schema + checklist. Autoloads handle "no save / fresh start" path.
- **Chunk loading (planned, post-v1 optimization, Plan D hybrid):**
  - **Chunk:** fixed tile grid, same size/shape across maps (map dimensions vary). Centered on the player with a buffer for pop-in prevention.
  - **Tiers:** Close (full sim + full render), Near (full NPC state, reduced tick rate, objects hidden, simplified collision), Far (identity preserved, tick rarely with large dt, coarse position, no render, coarse pathfinding).
  - **Promotion/demotion:** hysteresis (promote at inner radius, demote at outer radius + 1 chunk buffer); promotion interpolates position over ~0.5s.
  - **Tier radii:** chunk-radius based, configurable by player (optimization setting) with defaults (close 2, near 4, far beyond).
  - **Tick rates:** configurable; defaults close=every frame/period, near=every N frames/seconds, far=every 5–10s with large dt.
  - **`ChunkManager` autoload:** owns tier assignment, promotion/demotion with hysteresis, and the NPC tick scheduler. Config-level support for radii/tick rates; Options UI wiring deferred (surface feature).
  - **Map schema:** `chunk_size` (tiles) + derived chunk grid dimensions. Map renderer loads/unloads chunks around the player (Godot native culling for tiles; manual unload only beyond far threshold).
  - **NpcInstance additions:** runtime-only `tier` (close/near/far) and `coarse_position` (far); not persisted (recomputed on load).
  - **Interaction guard:** only close-tier NPCs are interactable; attempting to interact with a near NPC promotes it first.
  - **Save/load:** store all NPC state; tiers recomputed from player spawn position on load.
  - **Cross-chunk pathfinding (far):** coarse (straight-line), no per-object collision.
  - **Memory:** all NPC state in memory (v1); disk streaming deferred.
  - **Map editor:** chunks auto-derived from map dimensions + chunk size; editor shows chunk grid overlay.
  - **Scale target:** future very-large maps + 100s of NPCs (after-school activities); rates tunable then.

- **Minor implementation calls (recorded):**
  - Base content lives under `res://resources/` loaded directly; ModLoader exercised by one sample mod under `res://mods/`.
  - `Item` carries a `PackedScene` reference for instantiation.
  - NPC attendance simulated but perfect in v1.
  - NPC-initiated targeting: player or NPC, gated by outgoingness + not-busy + target chosen by familiarity/outgoingness.

## Testing Decisions

- **Seam:** highest seam — a single integration test at the day-loop level: spawn → move → talk → save → reload, verifying the slice end-to-end through `DebugStart.tscn`. Fewer seams is better; the ideal is one.
- **What makes a good test:** test external behavior, not implementation details. A test should assert observable outcomes (meters changed, save round-trips, mod registered, state machine transitions) rather than internal method calls or private fields.
- **Modules to test (via the day-loop seam):** ModLoader registration, SaveManager round-trip (instance state + template linkage), day state machine transitions, dialogue filtering + threshold resolution, meter updates on both parties, NPC AI goal selection (smoke), attendance + grade stub.
- **Prior art:** none — greenfield project; no existing tests. The day-loop integration test becomes the reference pattern for later slices.
- **Acceptance criteria (v1 slice is "done" when):**
  1. `DebugStart.tscn` runs a full day: Period1→FreeTime1→…→Period4→DayEnd→Save without errors.
  2. Player can move freely, approach an NPC, press E, pick from a 3–5 option pool, and see meters/mood update with feedback.
  3. At least one NPC initiates an interaction (player or NPC target) during free time.
  4. Save at DayEnd and reload restores player/NPC state (stats, mood, meters, positions, period) identically, with template linkage intact.
  5. A dropped mod folder with a valid `mod.json` is discovered and its resources registered at startup; an invalid/missing-dep mod is skipped with a log, no crash.
  6. Disabling a mod excludes its resources.
  7. A missing template on load is a recoverable error (no crash).
  8. Skip advances to the next period boundary.
  9. Attendance + grade stub runs on period change without errors.
  10. Code is commented describing functions/scripts.
11. (Post-v1, chunk loading) Chunk loading seams exist: `ChunkManager` autoload present (stub OK in v1), `chunk_size` field on `Map`, tier field on `NpcInstance`, hysteresis promotion/demotion documented. Full chunk-loading verification is a post-v1 acceptance item.

## Out of Scope

- Main menu, New Game flow, Load Game UI, Create Menu, Mods Menu, Options Menu (functional).
- Character/map creation tools and map editor.
- Weekend/season break choice pop-ups.
- Full academic system (basic grade-per-class stub only).
- Additional languages, audio polish.
- Performance tuning beyond ~5 NPCs (architecture must not preclude 30+ later).
- NPC override of existing resources by ID.
- NPC→NPC interactions beyond the single-initiator random-pick model (no complex negotiation).
- Network/HTTP endpoints (none; game is local).
- Chunk loading implementation (ChunkManager, tiered simulation, chunk-aware renderer, chunk grid overlay) — planned optimization; seams designed now, full implementation post-v1.
- Disk streaming of far chunks (deferred; in-memory for v1).
- Options UI for optimization settings (tier radii/tick rates) — deferred surface feature; config-level support in ChunkManager.

## Further Notes

- The spec follows the design doc `doc/idea-v1-brainstorming.md` (Approach A) and decisions in `doc/idea-v1-decisions.md`. Exact schema field lists, trait point costs, stat growth constants, goal-selection algorithm, dialogue condition syntax, save versioning, camera smoothing params, and dependency resolution algorithm details are left to the builder/plan.
- The `ready-for-agent` triage label applies; no additional triage needed.
- Base resources are authored by the developer in the Godot editor; the plan will include a schema + checklist.