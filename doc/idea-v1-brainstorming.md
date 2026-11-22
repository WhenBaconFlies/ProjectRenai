# Project Renai v1 — Design (Brainstorming)

Companion to `doc/idea-v1.md` (spec) and `doc/idea-v1-decisions.md` (clarification decisions).
Scope: **middle path** — load-bearing foundations + core loop vertical slice. Surface features deferred.

## 1. Intent and why

Build a modular, data-driven school-life simulation in Godot 4.2 (Windows desktop) whose heart is **romantic relationships and interacting character traits**. The defining requirement is **modularity**: characters, maps, dialogue, traits, and items are files (`.tres`) that can be dragged into another project or dropped into a `mods/` folder, and the game registers them automatically.

v1 is a **vertical slice**, not the full game: one map, 3–5 NPCs, free movement, one interaction type (talk), and save/load of a single day. Its job is to **prove the data model and modularity end-to-end** before any surface feature (menus, creation tools, mod UI, calendar screens) is built. The why is replayability and authorability: a builder should be able to add a character or a dialogue topic by dropping a file, with no code changes.

## 2. Goals, non-goals, anti-goals

**Goals (v1):**
- Prove the resource schemas (Character template, NPC instance, Map, DialogueTopic, Trait, Item) by real usage.
- Prove modularity: ModLoader discovers and registers dropped `.tres` resources via `mod.json`.
- Prove persistence: a day can be saved and reloaded, with instance state intact and template linkage preserved.
- Prove the core loop is fun: move, approach, talk, see meters move, feel traits matter.
- Establish the autoload/scene/data seams so later slices add features without rework.

**Non-goals (v1):**
- Main menu, New Game flow, Load Game UI, Create Menu, Mods Menu, Options Menu (shells may exist but are not required to be functional).
- Character/map creation tools and map editor.
- Weekend/season break choice pop-ups.
- Full academic system (only basic grade-per-class stub).
- Additional languages, SFX/music polish.
- Performance tuning beyond 3–5 NPCs (architecture should not preclude 30+ later).
- NPC counts > ~5.

**Anti-goals (what would make v1 a failure even if it technically works):**
- Hardcoded character/NPC/dialogue data that bypasses the resource system (kills modularity).
- A schema that can't be extended by a mod without code changes.
- Save files that can't be reloaded after a template changes (breaks the template+instance model).
- A day loop that can't be skipped or saved mid-flow (breaks "save at end of day" and playtesting).
- Implicit coupling between NPC runtime state and authored template data.

## 3. Constraints

- Engine: Godot 4.2, Forward Plus renderer.
- Platform: Windows desktop (v1).
- Languages: GDScript (gameplay/UI, editor tooling) + C# (data-heavy systems, registries, save serialization). Interop via Godot's C# ↔ GDScript bridge; keep the boundary at data/registry seams, not per-frame gameplay.
- Data format: Godot Resources (`.tres`) for characters/maps/traits/items/dialogue; JSON only for `mod.json` manifests.
- Saves: Godot Resource saves (`.tres`/`.res`), file-based, unlimited slots, in `user://`.
- Mod folder: `res://mods/` (v1); `user://mods/` later.
- Movement: free 2D on a tile-based grid; collision via Godot physics.
- Camera: follow player with smoothing.
- UI: simple but cute; minimap for navigation.
- Audio: music + SFX (volume controlled in Options; can be stubbed in v1).
- Localization: English only (v1); framework ready.
- Code: well-documented with comments describing functions/scripts.

## 4. Approaches considered

**A. Data-first vertical slice (chosen).**
Define resource schemas + registries first, then ModLoader + SaveManager, then one playable day. Each foundation is proven by real usage before the next is added.
- *Pros:* modularity proven by construction; schema changes caught early while cheap; vertical slice validates feel.
- *Cons:* slowest to "see something on screen" early; requires discipline to not skip ahead.

**B. Architecture-first full scaffold.**
Build all autoloads, scene shells, and empty menus first, then fill in data + gameplay.
- *Pros:* everything has a home from day one.
- *Cons:* empty shells invite premature abstraction; data model designed in the abstract with no usage feedback; higher schema-rework risk. Rejected: the data model is the load-bearing part, not the scene shells.

**C. Throwaway spike, then rebuild.**
Quickly build one interaction with hardcoded data to feel the game, discard, then build the real data-driven version.
- *Pros:* fastest feedback on feel and pacing.
- *Cons:* throwaway code can leak; does not exercise foundations (modding, saves) at all. Rejected: the foundations are the point of v1.

**Decision:** Approach A. The spec's central requirement (modularity) lives entirely in the data model; building data-first proves it before anything depends on it.

## 5. Foundations (how they get built)

### 5.0 Launch & entry point (v1)

A minimal debug launcher scene `DebugStart.tscn` auto-starts a default day (default map + player + 3–5 NPCs) with no menu flow, so the slice is runnable and testable immediately. Base resources (map, characters, dialogue topics, traits) are **authored by the developer in the Godot editor** first; the plan will include a schema + checklist of what to create, but not the asset authoring itself. Autoloads must handle a "no save / fresh start" path (DebugStart exercises it).

### 5.1 Folder layout
```
res://
  scenes/        # .tscn (MainMenu, Game, ...)
  scripts/       # GDScript + C#
  resources/     # .tres (characters, maps, traits, items, dialogue)
  assets/        # sprites, audio, fonts
  mods/          # mod folders, each with mod.json
  saves/         # runtime (user:// in production)
```

### 5.2 Autoloads (singletons)
- `GameManager` — global state, current save, scene transitions.
- `SaveManager` — save/load, slot management, instance↔template linkage.
- `TimeManager` — day clock, calendar, period tracking, drives the state machine.
- `ModLoader` — scans `res://mods/`, validates `mod.json`, resolves dependencies, registers resources.
- `AudioManager` — music/SFX, volume.
- `LocalizationManager` — string tables (English v1).

### 5.3 Resource schemas (data model)
- **CharacterTemplate** (`.tres`): identity (id, name, gender, orientation), appearance parts (hair, eyes, mouth, skin tone, outfit), traits (skills/interests/dislikes/personality), starting stats, stat growth modifiers, trait point cost. Authored/shared; immutable at runtime.
- **NpcInstance** (runtime, saved): template ID, current stats (base + deltas), mood (0–100), **per-instance directed meters** (`meters: { other_id → {familiarity, affection} }`), **per-instance schedule** (`schedule: period → named map marker`), position, current goal. References template by stable ID.
- **PlayerInstance**: same shape as NpcInstance but with free-choice interaction; available choices gated by stats + relationship.
- **Map** (`.tres`): tile data (grid of tile IDs), placed objects (list of {position, resource ref}), spawn point, navigation mesh data.
- **DialogueTopic** (`.tres`): id, text, conditions (mood/interest/trait/familiarity thresholds, required stat), checked stat, difficulty, success/failure affection deltas, familiarity delta, mood delta.
- **Trait** (`.tres`): id, category (skill/interest/dislike/personality), point cost, stat modifiers (starting + growth), tags.
- **Item** (`.tres`): id, type, `PackedScene` reference (for instantiation), sprite/collider data, properties (for furniture/walls used by map editor).

Exact field lists and defaults are left to the builder, but the schemas above are the contract.

### 5.4 Template ↔ instance linkage
Instances store a stable **template ID** string (e.g., `char:student_001`). `ModLoader` maintains an ID→resource registry built at startup. Saves store IDs, not paths or UIDs, so templates can move/rename without breaking saves (as long as IDs stay stable). A missing template on load is a recoverable error (instance marked invalid, not a crash).

### 5.5 Mod loader contract
- Scan `res://mods/` at startup.
- Each mod folder must contain `mod.json`: `{ name, version, author, entry (script path), dependencies: [mod ids], content: [resource paths] }`.
- Validate: manifest present, entry script loads, dependencies fulfilled (all declared deps present and version-compatible). On failure, log and skip the mod (do not crash).
- Register: entry script calls registration APIs to add resources to the appropriate registries.
- Enable/disable: a flag (file or Mods Menu state) per mod; disabled mods are skipped.
- Dependency resolution: topological order by declared deps; cycle detection rejects the cycle.
- v1 is **add-only**: mods add new resources; overriding existing IDs is not supported (avoids conflicts). Override can be added later.

### 5.6 Save system
- Save the whole game state as a Godot Resource (`.tres`/`.res`): current day, period/state, player instance, NPC instances, relationship meters, positions, mood, stats.
- Unlimited slots, file-based in `user://`.
- Autosave + manual (player-triggered).
- No day-end summary screen; save prompt only.
- Save version field for forward compatibility; migration handled by SaveManager.

### 5.7 Day state machine
Explicit enum states, each owning its logic:
`Period1 → FreeTime1 → Period2 → FreeTime2 → Period3 → FreeTime3 → Period4 → DayEnd → Save → NextDay` (or Quit).
- On period change: NPCs move to class locations; attendance recorded; grade computed (attendance + INT/WIS) → small stat bonus.
- Free time: player roams; NPCs run goal-driven AI; interaction available.
- DayEnd: autosave + manual save prompt.
- Skip: advances to next period boundary (time jumps, no simulation in skipped class time).
- Break days (weekends/seasons) are a separate state not exercised in v1.

### 5.8 NPC goal-driven light AI (free time)
Each NPC picks a goal from: traits (interests), current mood, and relationship meters (seek out friends/love interests, avoid enemies). Goal → destination (a hangout spot or another NPC). Movement via `NavigationAgent2D` on a baked navmesh. Goals re-evaluate on period change or when reached. Keep it simple and deterministic-ish; no complex planning.

**NPC-initiated interactions:** An NPC with sufficient outgoingness may initiate an interaction with another character (player or NPC) when it is not already pursuing a goal, choosing the target from familiarity/outgoingness. The initiator then receives the same filtered dialogue pool as a player would and **picks one option at random** to complete the interaction; the threshold roll and deltas apply to both parties' directed meters. This makes the interaction pipeline pair-agnostic (initiator_id, target_id). Attendance: NPCs simulate attendance per period (perfect in v1 — their only goal is to attend; no repercussions).

### 5.9 Interaction & dialogue
- Trigger: `Area2D` proximity + E keypress (player-initiated), or NPC initiation (outgoingness + not-busy, target chosen by familiarity/outgoingness) — handled by an `InteractionComponent`.
- The interaction pipeline is **pair-agnostic** `(initiator_id, target_id)`: filter all `DialogueTopic` resources whose conditions pass → random pool of 3–5. Player picks manually; NPC initiator picks at random.
- Resolution: threshold check `stat + (familiarity/10) + random(0..5) >= difficulty` (difficulty per topic, may incorporate recipient stats/traits). Margin scales the affection delta.
- Effects applied to **both parties' directed meters**: affection delta, familiarity delta, mood delta (per topic, success/failure variants).
- Relationship type derived from meters (Stranger/Friend/Enemy/Lover) with mutual romance gating (orientation + gender + thresholds).

### 5.10 Stats & growth
- Stats: STR, DEX, CON, INT, WIS, CHA (gate dialogue options + affect success).
- Traits set starting stats and modify growth rates.
- Growth via break activities + interactions (study→INT, socialize→CHA, etc.); traits modify rate. In v1, growth is exercised lightly (single day) but the pipeline must exist.

### 5.11 Camera
Follow player with smoothing (Camera2D with smoothing). Minimap as a secondary view.

### 5.12 Mood
Numeric 0–100, clamped. Affects dialogue eligibility and (lightly) stat checks. Updated by interaction outcomes.

### 5.13 Chunk loading (planned, post-v1 optimization)
Fixed tile grid chunks (same size/shape across maps; map dimensions vary). Centered on the player with a buffer for pop-in prevention. Three tiers: Close (full sim + full render), Near (full NPC state, reduced tick rate, objects hidden, simplified collision), Far (identity preserved, tick rarely with large dt, coarse position, no render, coarse pathfinding). Promotion/demotion uses hysteresis (promote at inner radius, demote at outer radius + buffer); promotion interpolates position over ~0.5s. Tier radii and tick rates are configurable by the player (optimization setting); defaults provided. Only close-tier NPCs are interactable; attempting to interact with a near NPC promotes it first. NPC state stays in memory (v1); disk streaming deferred. Far-future goal: extend maps beyond school (very large maps, 100s of NPCs); rates tunable then. All NPC state stored on save; tiers recomputed from player spawn position on load.

## 6. Core loop (the vertical slice)

1. Load map `.tres` → renderer builds tilemap + objects + navmesh.
2. Spawn player at map spawn point; spawn 3–5 NPCs from template IDs (ModLoader registry).
3. State machine starts at Period1.
4. Player moves (free 2D), camera follows, minimap updates.
5. Free time: player approaches NPC, presses E → dialogue pool → pick option → threshold roll → meters/mood update → feedback shown (meter change, default on).
6. NPCs run goal-driven AI, move, and may initiate interactions (outgoing based on outgoingness trait).
7. Period changes: NPCs move to class; attendance + grade stub; stat bonus.
8. DayEnd: autosave + manual save prompt.
9. Save reloads the day identically (instance state + template linkage).

## 7. What's left to the builder

- Exact resource schema field lists and defaults.
- Trait list and point costs (data files).
- Stat growth formula constants.
- Goal-selection algorithm details and tuning.
- Dialogue topic field list and condition syntax.
- Save versioning/migration details.
- Camera smoothing parameters.
- Navigation mesh baking details and performance.
- Dependency resolution algorithm specifics (topological sort + cycle detection).
- Interaction feedback UI specifics (how meter changes are shown).
- NPC count/performance profiling for >5 (deferred but architecture should not block).

## 7.5 Minor implementation calls (settled by builder, recorded for review)

- **Base content packaging:** Base resources live under `res://resources/` and are loaded directly; ModLoader is still exercised end-to-end by one sample mod under `res://mods/`. Keeps gameplay runnable without blocking on full ModLoader completeness, while still proving modularity.
- **Placed map objects:** The `Item` resource carries a `PackedScene` reference (plus sprite/collider data) that the renderer instantiates. Aligns the Item schema and renderer contract.
- **NPC attendance (v1):** Simulated but perfect — NPCs' only goal is to attend class; no repercussions. Grade stub uses attendance + INT/WIS → small stat bonus (player only; NPC grades not surfaced).
- **NPC-initiated interaction targeting:** Can target player or other NPCs (pair-agnostic pipeline). Initiation gated by outgoingness trait + not-busy + target chosen by familiarity/outgoingness.
- **Chunk loading (post-v1):** Fixed tile grid chunks, same size/shape across maps; player-centered with buffer. Tier radii and tick rates configurable by player (optimization setting) with defaults. Hysteresis buffer of 1 chunk (promote at inner radius, demote at outer+1). Promotion interpolates position over ~0.5s. Far NPCs use coarse (straight-line) pathfinding. Near-chunk collision is simplified (no per-furniture). Interaction guard promotes near NPC on interaction attempt. Disk streaming deferred; in-memory for v1. Config-level support in ChunkManager; Options UI wiring deferred to surface feature.

## 8. Approval

This design is a proposal. Please confirm or correct before I (or a plan) proceeds to implementation. Key things to rubber-stamp:
- Approach A (data-first vertical slice).
- Template + instance data model with stable template IDs and per-instance directed meters.
- `.tres` for maps and resources, Godot Resource saves.
- Explicit day state machine with per-instance NPC schedules.
- Goal-driven light NPC AI with NPC-initiated (player or NPC) interactions.
- Data-driven dialogue with threshold checks and topic-defined deltas (pair-agnostic pipeline).
- Mod loader with `mod.json`, dependencies, enable/disable, add-only.
- Debug launcher `DebugStart.tscn`; base resources authored in editor.
- NPC attendance simulated (perfect) in v1.
- Chunk loading (post-v1): fixed tile grid, player-centered with buffer, three tiers with hysteresis, promotion interpolation, coarse pathfinding, configurable radii, interaction guard, in-memory (disk streaming deferred).