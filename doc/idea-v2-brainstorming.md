# Project Renai v2 — Design (Brainstorming)

Companion to `doc/idea-v2.md` (goal + requirements), `doc/idea-v2-decisions.md` (decision record), and `doc/idea-v1-final.md` (v1 baseline).
Approach: **A — pure conversation helper + thin wiring**. Surface build order in §7.

## 1. Intent and why

v1 delivered a playable debug slice with solid systems (resource schemas, registries, day state machine, pair-agnostic dialogue, relationship meters, NPC AI, modding, save/load, chunk seams) but no way for a player to reach them: it launches straight into a day, saving is F5/F9, and a "conversation" is one question and a meter change. v2's job is to **make conversations feel like conversations** — an NPC greets you, you speak, they react differently depending on the outcome and your relationship — and to wrap that in a **minimal player-facing shell** with enough authored content that the social simulation has room to express itself. The why: romance and interacting traits are the heart of Project Renai; v1 proved the systems, v2 makes the central experience legible.

## 2. Goals, non-goals, anti-goals

**Goals:**
- Multi-exchange conversations with authored greetings, player topics, and reactive NPC responses.
- A full-screen dialogue overlay over the visible world (portrait slots reserved, not implemented).
- Distinct `.tres` resource types for greetings, topics, and responses, all moddable.
- ~40–60 dialogue topics and ~15–20 new traits authored as data.
- Main Menu, Load Game (named slots), Options, Mods Menu, and an in-game pause overlay.
- Relationship-driven NPC goals (seek friends/lovers, avoid enemies).
- Persistent headless tests covering the new flows; v1 harnesses still pass.

**Non-goals (v3 or later):**
- Functional New Game wizard (map/NPC-count/character selection), character creation, map editor.
- Calendar and weekend/season break choice pop-ups.
- Full academic system; additional languages; audio polish.
- Performance tuning beyond ~4 NPCs; disk streaming of far chunks.
- Relationship-feedback toggle UI; portrait art implementation.

**Anti-goals (what would make v2 a failure even if it works):**
- Hiding the world behind a full art backdrop instead of an overlay.
- Hardcoding dialogue lines or responses in scripts, bypassing `.tres`/modding.
- A conversation that still ends after one pick with no reactive reply.
- Growing `Game.gd` into a monolith that cannot be tested headlessly.
- Menus that route around the existing `GameManager`/`SaveManager` seams.

## 3. Constraints

- Engine: Godot 4.2 (Forward Plus), Windows desktop, GDScript only (no C# migration in v2).
- ~4 NPCs on the shipped 1×1-chunk debug map; chunk loading stays synthetic-test-only.
- v1 architecture is preserved and extended: `ModLoader` registries, `DialogueFilter`/`DialogueResolver` pure helpers, `NpcInstance` shape, `TimeManager` state machine, `SaveManager` slots, `ChunkConfig`, `Npc`/`NpcAi`, and the `tests/` harness pattern.
- All new content authored as `.tres` in the editor; no content hardcoded.
- Save format stays Godot Resource `.tres` slots in `user://`.
- UI style remains "simple but cute" (`idea-v0.md`); v1 has no art assets, so overlay/menu visuals use generated shapes, colors, and text.
- Settings store is a `ConfigFile` in `user://`; English is the only language (disabled selector in Options).
- Feedback flag remains a save-payload field plus runtime API, not an Options control.

## 4. Approaches considered

**A. Pure conversation helper + thin wiring (chosen).**
Add a `Conversation` `RefCounted` helper owning session state (phase, turn count ≤ 2, ids, seeded RNG). Extend `DialogueFilter` with greeting/response eligibility + pool selection; extend `DialogueResolver` to resolve a `DialogueResponse` carrying its own roll fields as well as a `DialogueTopic`. A new `ConversationUI` overlay shows speaker + line + choices over the world. `Game.gd` connects signals, owns the clock/input lock, and forwards selections.
- *Pros:* Matches v1's proven pure-helper + thin-wiring pattern; headless-testable at the conversation seam; one place owns the 2-exchange rule; Game.gd stays thin.
- *Cons:* More seams (helper, UI, filter/resolver extensions); helper must stay scene-tree-free.

**B. Conversation state machine inside Game.gd.**
- *Pros:* Fewest new classes; fastest to first conversation.
- *Cons:* Game.gd is already ~890 lines; would push past ~1,300 and make the 2-exchange flow untestable without the full scene. Rejected: repeats the problem v1 avoided with pure helpers.

**C. Conversation subsystem scene with its own controller node.**
- *Pros:* Strong encapsulation; reusable in other scenes; visual editing of the overlay.
- *Cons:* Per-interaction instantiate/free lifecycle and heavier headless testing; unnecessary for one conversation at a time. Rejected: a pure helper is sufficient.

**Decision:** Approach A. The conversation is pure data + turn rules; it does not need a scene lifecycle, and the rules do not belong in Game.gd.

## 5. How it gets built (decided parts)

### 5.1 Resource schemas (three distinct `.tres` types)
- **`DialogueGreeting`** (`class_name DialogueGreeting extends Resource`): `id`, `text`, eligibility fields — relationship type (one of the five from `DialogueResolver`), mood band, period/time-of-day, required trait/interest ids/tags — plus a seeded-priority or weight field. Registered in a new `TYPE_GREETING` bucket via `ModLoader`.
- **`DialogueTopic`** (existing, extended): unchanged role — player's choice text, conditions, checked stat, difficulty, success/failure deltas, recipient modifiers. Registered in `TYPE_DIALOGUE`.
- **`DialogueResponse`** (`class_name DialogueResponse extends Resource`): `id`, `text` (the NPC's spoken line), `topic_id` (the topic it answers), outcome (`success`/`failure`), relationship band = the **five derived types** from `DialogueResolver.relationship_type()`, and **its own roll fields** — `checked_stat`, `difficulty`, and success/failure affection/familiarity/mood deltas. When those roll fields are empty it is a line-only reaction; when populated it is resolvable as a normal roll (used for the player's reply to an NPC-initiated topic). Registered in a new `TYPE_RESPONSE` bucket.
- All three types are authored as `.tres` and moddable by dropping files. Add-only duplicate-ID rules still apply.

### 5.2 Conversation helper (`Conversation.gd`)
- `class_name Conversation extends RefCounted`, pure (no scene tree, no autoload globals; reads instances/templates passed in, seeded RNG like the v1 helpers).
- Owns: phase enum (`GREETING`, `TOPIC`, `RESPONSE`, `FOLLOWUP`, `DONE`), `turn` count (max **2 player picks**), `initiator_id`, `target_id`, `open` flag, and a seeded `RandomNumberGenerator`.
- Public seams (proposed): `begin(initiator, target, templates, seed)`, `choose_greeting(greetings, ...)`, `build_topic_pool(topics, ...)`, `build_reply_pool(responses, ...)`, `select_response(...)`, `advance()`, `is_done()`, `snapshot()`/`restore` if needed. Exact signatures left to the builder, but the helper must expose a headless-testable seam for every phase.
- **2-exchange rule:** Greeting → player topic → NPC response → optional second topic + response → leave. The greeting is not counted as an exchange. Each player pick gets its own roll through `DialogueResolver`.

### 5.3 Dialogue pipeline extensions
- `DialogueFilter`: add `select_greeting(greetings, initiator, target, templates, seed)` and `select_responses(responses, topic_id, outcome, relationship_type, ...)`. Keep eligibility read-only and seeded. The 5-type relationship band comes from `DialogueResolver.relationship_type()` on the post-roll instances, evaluated for the **responder toward the speaker** — for player-initiated, the NPC's meter toward the player, since that is what the NPC's spoken line expresses.
- **Response fallback:** eligibility falls back in layers — exact `(topic, outcome, band)` → authored default for the topic (`band`/`outcome` blank) → generic authored line → code-generated line. The authoring checklist requires one default response per topic, and a headless test asserts the fallback fires when no exact match exists.
- `DialogueResolver`: add `resolve_response(response, initiator, target, templates, seed)` that reuses the existing roll, margin scaling, recipient modifiers, dual-party meter/mood writes, and relationship derivation. A `DialogueResponse` with no roll fields resolves to a line-only outcome (no deltas) for the NPC reaction step.
- Relationship derivation stays on demand (no persisted type field); v1's five types and mutual-romance gate are unchanged.

### 5.4 UI (`ConversationUI.gd` / scene)
- A `Control` overlay anchored to the bottom: semi-transparent panel showing speaker name and the current spoken line, with 3–5 numbered choices stacked beneath; the school world stays visible behind it.
- Two reserved transparent portrait slots (speaker left, listener right) are laid out but **not implemented in v2** — placeholder nodes only.
- Replaces `DialoguePoolUI` for conversations but can keep it as a fallback/legacy component. Number keys, Esc (cancel when open), and mouse accepted.
- Shows the NPC greeting, the player's topic text, and the reactive response text in sequence; meter feedback continues via the existing `InteractionFeedbackUI` after each turn.

### 5.5 NPC-initiated flow (unique shape)
- An outgoing NPC in free time picks its own topic (as v1 does), **speaks that topic's text as its opening line**, then the player chooses from a **fixed 2–3** `DialogueResponse` reply options filtered by traits/mood/modifiers.
- **The NPC's opening topic does not roll and applies no deltas** — it is spoken only, so the player's reply truly produces the final change.
- **Reply selection key:** replies are chosen by `topic_id` plus trait/mood/interest filters (not by outcome/band, which do not exist yet at selection time). In this flow `DialogueResponse.text` is the **player's spoken line** — a role inversion from the player-initiated case where it is the NPC's reaction.
- **Roll direction:** the reply roll uses the **player as initiator**, the NPC as target, so the existing `DialogueResolver` arguments stay natural. Its deltas are the final affection/mood change; one player response then the conversation ends.
- Gating: free time only **now**, but via a callable/condition rather than a hardcoded state check, so future "both skipping class" cases can be added without restructuring.
- Player input is locked during the reply, same as player-initiated; existing busy set and hold timers still apply.

### 5.6 Menus and shell (separate scenes)
- `MainMenu.tscn` (New Game, Load Game, Options, Mods Menu, Quit) becomes `run/main_scene`. `DebugStart.tscn` stays as a developer shortcut; New Game calls `GameManager.start_fresh_day()` (the same path DebugStart uses).
- `LoadGame.tscn`: list/load/delete named slots (existing `SaveManager` API); **create named slot from the pause overlay only**, writing the current live state via `SaveManager.save_slot(name)`.
- `Options.tscn`: Volume, Chunk settings (radii/tick rates from `ChunkConfig`), Language display (English, disabled selector), Resolution (windowed presets + fullscreen). **All changes apply immediately** with a notice where a restart is actually required. Feedback toggle is deliberately absent.
- `ModsMenu.tscn`: list installed/enabled mods with an enable/disable toggle. The menu writes the enable/disable flag to `user://settings.cfg`; `ModLoader` reads enabled/disabled state from there (not from a `res://` `.disabled` marker). Change takes effect **on next launch** (restart-required notice, no live rescan).
- **Deployment:** support both project-local and exported builds — bundled base mods stay in `res://mods/`, and an additional `user://mods/` scan root is added for user-installed mods. `ModLoader` scans both roots; enable/disable flags live in settings so the menu works in a read-only `res://` export.
- `PauseMenu.tscn`: in-game overlay via Escape **only when no conversation is open** (the conversation owns Escape while open).
- All screens route through `GameManager.change_scene()` and existing autoloads; no parallel state machinery.

### 5.7 Settings store
- New `SettingsManager` autoload backed by `ConfigFile` at `user://settings.cfg`, holding volume, resolution/fullscreen, chunk config values, and language display.
- Applies on startup to `AudioManager`, `DisplayServer`, and `ChunkManager.config`; Options writes through it immediately.

### 5.8 Content expansion
- ~40–60 dialogue topics total across greetings, player topics, and responses; ~15–20 new traits across skills/interests/dislikes/personality with point costs and tags.
- Authored as `.tres` in `resources/`; base content registered by `ModLoader` alongside existing base characters/topics. Tags feed greeting variation, response filtering, and NPC goals.

### 5.9 NPC AI
- Wire `NpcAi.relationship_candidates()`: directed familiarity/affection meters weight free-time goals — seek friends/love interests, avoid enemies. Interest/mood goals remain; no complex negotiation.

### 5.10 Verification
- Extend the persistent `tests/` harness pattern (headless Godot, marker-based pass/fail). New harnesses cover: greeting selection by all four factors, 2-exchange limit, player-topic roll + reactive response, both parties' meters, NPC-initiated single-response shape and free-time gate, menus/save naming/options/mods toggles, settings persistence, relationship-driven goals.
- Re-run v1's day-loop, chunk-renderer, and chunk-manager harnesses as regressions; all v1 acceptance criteria must still pass.
- RED/GREEN proof at least once on a core conversation check, as in v1's ticket 018.

## 6. Risks and open items
- **Response contract complexity:** a `DialogueResponse` that can be line-only or rollable risks ambiguous authoring. Mitigation: clear defaults (empty roll fields = line-only) and an authoring checklist; layered response fallback (exact → topic default → generic authored → generated) means a missing match never dead-ends a conversation.
- **Greeting banding:** four variation factors can under-specify a greeting. Mitigation: seeded weighting with a safe fallback (any eligible greeting) so a conversation always opens.
- **Settings immediacy:** applying resolution/chunk config live may need care with `DisplayServer` and a running `ChunkManager`. Mitigation: Options writes immediately but shows a restart notice where the engine requires it.
- **Mods Menu in exported builds:** `res://` is read-only in an export. Mitigation: user-writable `user://mods/` scan root plus enable/disable flags in `user://settings.cfg`; base mods remain bundled in `res://mods/`.
- **Game.gd regression:** v1's F5/F9 hotkeys and pause/Escape interaction must keep working. Mitigation: the pause gate checks `Conversation.is_open()` first.

## 7. Build order
1. Three schemas (`DialogueGreeting`, `DialogueResponse`, `TYPE_GREETING`/`TYPE_RESPONSE` buckets) + registration.
2. Content authoring (~40–60 topics, ~15–20 traits).
3. `Conversation` helper + `DialogueFilter`/`DialogueResolver` extensions.
4. `ConversationUI` overlay + `Game.gd` wiring (replace one-pick flow).
5. `SettingsManager` + Options screen.
6. Main Menu, Load Game, Mods Menu, Pause Menu scenes + GameManager routing.
7. Relationship-driven NPC goals.
8. Tests + v1 regression run.

## 8. What's left to the builder
- Exact field lists/defaults for the three schemas (esp. greeting weight and response roll-field defaults).
- Exact `Conversation` method signatures and phase enum names.
- Whether `Conversation` needs snapshot/restore for mid-conversation saves (assumption in `idea-v2.md`: saves happen between turns).
- Exact resolution presets and ConfigFile keys.
- Exact menu visual styling and widget layout; placeholder portrait visuals.
- Exact trait names/costs and topic distribution across the three types.
- Exact test counts and thresholds; which functions must be documented for the comment audit.

## 9. Approval
Approved by the human partner, including the four builder-check resolutions: layered response fallback, NPC-initiated reply contract (spoken-only opening, replies keyed by topic + filters, player as roll initiator, response text is the player's line), responder's relationship type keys a response, and dual `res://mods/` + `user://mods/` with settings-based enable/disable. Design is final; next step is the implementation plan.
