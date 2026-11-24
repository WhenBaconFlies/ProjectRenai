# Project Renai v2 — Spec

Companion to `doc/idea-v2.md` (goal + requirements), `doc/idea-v2-brainstorming.md` (design), and `doc/idea-v2-decisions.md` (decisions).
Strategy: **A — pure conversation helper + thin wiring**, with build order in the design doc.

## Problem Statement

A player who has the v1 Project Renai slice can move around a school, talk to NPCs, and watch relationship meters change — but a "conversation" is one question and a number, there is no way to start a game or load a save without developer hotkeys, and no way to change settings or mods. The developer wants v2 to turn that slice into something a player can actually play and stay with: conversations that have a greeting, a spoken reply, and reactive responses that depend on how the exchange went and on the relationship between the characters, wrapped in a minimal menu shell.

The defining requirement is that this stays **modular and data-driven**: greetings, topics, and NPC responses are `.tres` resources that can be authored in the editor or dropped into a mod folder with no code changes. v2 deepens the thing that makes the game distinctive (romance + interacting traits) and adds just enough interface and content to reach it.

## Solution

Build v2 as a **pure-helper + thin-wiring extension** of v1's architecture:

1. Add three distinct `.tres` resource types in three `ModLoader` buckets: `DialogueGreeting` (opening line + eligibility), the existing `DialogueTopic` (player's choice), and `DialogueResponse` (spoken line, keyed by topic/outcome/relationship band, with its own optional roll fields).
2. Add a pure `Conversation` helper that owns session state — phase, turn count (max 2 player picks), ids, seeded RNG — and extend `DialogueFilter`/`DialogueResolver` to select greetings/responses and resolve a `DialogueResponse` as a normal roll.
3. Replace the one-pick flow with a `ConversationUI` overlay over the visible world: greeting → player topic → reactive NPC line → optional second topic+response → leave. NPC-initiated interactions take their unique single-reply shape.
4. Add a slim player-facing shell: Main Menu, Load Game (named slots), Options, Mods Menu, and an in-game Pause Menu, plus a `ConfigFile` settings store. Wire relationship-driven NPC goals.
5. Author ~40–60 dialogue topics and ~15–20 new traits as `.tres`, and verify everything with one persistent integration harness that re-runs v1's harnesses as regressions.

## Scope

**In scope for v2:**
- Three-resource dialogue data model and its modding/registry support.
- Multi-exchange conversations (player-initiated, max 2 picks; NPC-initiated, one reply) with fallback behavior when content is missing.
- The world-visible conversation overlay with reserved (unimplemented) portrait slots.
- ~40–60 topics and ~15–20 new traits authored as data.
- Main Menu, Load Game with full named-slot UI, Options, Mods Menu, Pause Menu, and settings persistence.
- NPC-initiated conversations and relationship-driven NPC goals.
- Headless verification via one integration harness; v1 harnesses remain green.

**Out of scope for v2:** see Out of Scope below.

## User Stories

1. As a player, I want an NPC to greet me with a line that fits our relationship, mood, the time of day, and our traits, so that the world feels responsive.
2. As a player, I want to pick a topic and hear the NPC say something back that depends on whether my approach worked, so that a talk feels like a conversation rather than a menu transaction.
3. As a player, I want a second exchange after the first, so that a conversation can build momentum.
4. As a player, I want to leave a conversation when I choose, so that I control my time.
5. As a player, I want the school world to stay visible while I talk, so that I do not lose my place in the day.
6. As a player, I want speaker names and numbered choices in the dialogue overlay, so that I know who is talking and how to respond.
7. As a player, I want to reply to an NPC who approaches me, so that their initiative leads somewhere.
8. As a player, I want my reply to an approaching NPC to determine the final affection/mood change, so that my response matters.
9. As a player, I want NPCs to sometimes talk to each other, so that the school feels alive.
10. As a player, I want relationship types like Friend or Lover to change how characters speak to me, so that progress is visible.
11. As a player, I want a greeting even when no perfect authored line exists, so that conversations never dead-end.
12. As a player, I want a reactive line even when no exact response matches, so that every choice gets an answer.
13. As a player, I want a Main Menu so that I can start, load, configure, or quit the game.
14. As a player, I want New Game to start a day directly, so that I do not need to know debug controls.
15. As a player, I want to name, load, and delete save slots from a screen, so that I can manage my progress.
16. As a player, I want to create a named save slot while playing, so that I can save at a moment I choose.
17. As a player, I want to load a save and find my day, stats, meters, and positions restored, so that progress is reliable.
18. As a player, I want to adjust volume, resolution, chunk settings, and see the current language, so that the game fits my machine.
19. As a player, I want settings changes to take effect right away, so that I get immediate feedback.
20. As a player, I want to pause the game and reach save/load, so that I can manage the session mid-day.
21. As a player, I want Escape to cancel a conversation while it is open and pause the game otherwise, so that one key does the intuitive thing.
22. As a modder, I want greetings, topics, and responses as separate `.tres` files, so that I can add each kind of content independently.
23. As a modder, I want a response to carry its own roll fields, so that a player reply can resolve without referencing another resource.
24. As a modder, I want duplicate IDs rejected add-only, so that mods cannot silently override base content.
25. As a modder, I want to enable or disable mods from a menu, so that I can troubleshoot my install.
26. As a modder, I want enable/disable to survive in exported builds, so that the menu works in the shipped game.
27. As a modder, I want user-installed mods scanned from a user-writable folder, so that I do not need to edit the game install.
28. As a developer, I want settings in a user `ConfigFile`, so that changes persist across launches.
29. As a developer, I want a pure `Conversation` helper, so that the 2-exchange rule is testable without a scene.
30. As a developer, I want filter/resolver extensions to stay read-only/seeded, so that headless tests are deterministic.
31. As a developer, I want one integration harness, so that the whole v2 flow is verified at the highest seam.
32. As a developer, I want v1's harnesses re-run as regressions, so that v2 does not break v1.
33. As a developer, I want one default response authored per topic, so that content coverage is predictable.
34. As a developer, I want a fallback chain for responses, so that missing content never blocks a conversation.
35. As a player, I want NPCs to seek friends and love interests and avoid enemies, so that relationships change behavior.
36. As a player, I want more traits with skills/interests/dislikes/personality, so that characters feel distinct.
37. As a developer, I want ~40–60 authored topics, so that conversations have variety.
38. As a player, I want feedback after each turn, so that I can see how the relationship changed.
39. As a developer, I want portrait slots reserved but not implemented, so that art can be added later without UI rework.
40. As a player, I want NPC-initiated replies to use fixed 2–3 options, so that the interaction stays short.
41. As a developer, I want the NPC's opening line in an NPC-initiated talk to apply no deltas, so that the player's reply is the final change.
42. As a developer, I want the responder's relationship type toward the speaker to key responses, so that spoken lines match the speaker's feelings.

## Implementation Decisions

- **Strategy:** Approach A (pure `Conversation` helper + thin `Game.gd` wiring). Approach B (state machine inside Game.gd) and C (conversation subsystem scene) were rejected.
- **Modules:**
  - `Conversation` (new, `RefCounted`, pure) — session state: phase enum (`GREETING`/`TOPIC`/`RESPONSE`/`FOLLOWUP`/`DONE`), turn count ≤ 2, initiator/target ids, seeded RNG. No scene-tree or autoload references.
  - `DialogueFilter` (extended) — greeting selection and response selection, read-only and seeded, with the layered response fallback.
  - `DialogueResolver` (extended) — `resolve_response()` reusing roll, margin scaling, recipient modifiers, dual-party meter/mood writes, and relationship derivation; line-only responses produce no deltas.
  - `ConversationUI` (new) — world-visible bottom overlay with speaker name, line, and numbered choices; portrait slots reserved only.
  - `Game.gd` (modified, thin) — connects signals, owns input/clock lock, forwards selections, replaces the one-pick close path.
  - `SettingsManager` (new autoload) — `ConfigFile` at `user://settings.cfg` for volume, resolution/fullscreen, chunk config, language display; writes apply immediately.
  - `ModLoader` (extended) — `TYPE_GREETING` and `TYPE_RESPONSE` buckets; scans `res://mods/` and `user://mods/`; reads enable/disable from settings rather than `res://` `.disabled` markers; add-only conflict rules unchanged.
  - `GameManager` (extended) — routes to the new menu scenes; `MainMenu.tscn` becomes `run/main_scene`; `DebugStart.tscn` kept as developer shortcut.
  - `NpcAi` (extended) — `relationship_candidates()` wired so directed meters weight free-time goals (seek friends/lovers, avoid enemies); interest/mood goals remain.
  - Menu scenes: `MainMenu`, `LoadGame`, `Options`, `ModsMenu`, `PauseMenu` (separate scenes, routed through GameManager).
- **Schemas:**
  - `DialogueGreeting` (`.tres`) — id, text, eligibility fields: relationship type, mood band, period/time-of-day, required trait/interest ids/tags, weight.
  - `DialogueTopic` (existing) — player's choice text, conditions, checked stat, difficulty, success/failure deltas, recipient modifiers.
  - `DialogueResponse` (`.tres`) — id, text, `topic_id`, outcome, relationship band = the five derived relationship types, and its own roll fields (checked stat, difficulty, success/failure affection/familiarity/mood deltas). Empty roll fields = line-only reaction. In NPC-initiated replies, `text` is the player's spoken line.
- **Relationship band:** derived via `DialogueResolver.relationship_type()` for the **responder toward the speaker** (player-initiated: NPC toward player). Five types unchanged; mutual romance gate unchanged; no persisted type field.
- **Response fallback chain:** exact `(topic, outcome, band)` → authored default for the topic (blank band/outcome) → generic authored line → code-generated line. Authoring checklist requires one default response per topic; a test asserts the fallback fires.
- **Player-initiated flow:** greeting → player topic (roll) → NPC response line → optional second topic + response → leave. Two player picks maximum; greeting not counted. Feedback after each turn.
- **NPC-initiated flow:** outgoing NPC in free time picks its own topic, speaks it as its opening line **with no roll/deltas**; player picks from fixed 2–3 reply `DialogueResponse` options keyed by `topic_id` + trait/mood/interest filters; the reply is resolved with the **player as initiator**, NPC as target, using the response's own roll fields; its deltas are the final change; one reply then end. Input locked during reply. Gating via a condition/callable (free time now, future cases possible).
- **Settings:** `ConfigFile` store; all changes apply immediately; a restart notice is shown only where the engine requires it. Resolution = windowed presets + fullscreen (exact presets builder-choice). Language = English shown as current with disabled selector. Relationship-feedback toggle deliberately absent from Options; it stays a save-payload flag and runtime API.
- **Saves:** full named-slot UI — create (pause overlay only, from current live state), load, delete; available from Main Menu and pause overlay; F5/F9 debug hotkeys remain.
- **Mods:** menu lists mods with enable/disable writing to settings; dual scan roots (`res://mods/` bundled, `user://mods/` user-installed); changes take effect on next launch (restart notice, no live rescan).
- **Content:** ~40–60 topics total across greetings/topics/responses and ~15–20 new traits with point costs and tags, authored as `.tres` and registered as base content. Exact trait names/costs and topic distribution are builder-choice.
- **NPC AI:** `NpcAi.relationship_candidates()` wired for seek friends/lovers and avoid enemies; no complex negotiation.

## Testing Decisions

- **Seam:** one persistent integration harness at the highest seam — `MainMenu`/New Game → conversation (greeting, player topic, reactive response, both meters, 2-exchange limit, player- and NPC-initiated shapes) → menus/settings/mods → save/reopen → relationship-driven goal. Fewer seams is better; the ideal is one.
- **What makes a good test:** assert external behavior only — lines shown, turn count, meters/mood, relationship type, saved state round-trip, slot operations, settings persistence, mod enable/disable — not internal method calls or private fields.
- **Modules exercised via the seam:** `Conversation` phase/turn rules, `DialogueFilter` greeting/response selection and fallback, `DialogueResolver.resolve_response`, `ConversationUI` overlay states, `SettingsManager` persistence and application, the five menu scenes, `ModLoader` dual-root scan and settings-based enable/disable, `SaveManager` named slots, `NpcAi` relationship goals.
- **Prior art:** v1's persistent `tests/` harnesses (`DayLoopIntegrationTest`, `ChunkRendererTest`, `ChunkManagerTest`) with marker-based pass/fail, deterministic clock control via `TimeManager.advance()`, seeded RNG, and RED/GREEN proofs. v2 reuses this pattern and re-runs all three v1 harnesses as regressions.
- **Acceptance criteria (v2 is "done" when):**
  1. A player-initiated conversation shows an authored greeting appropriate to relationship/mood/period/traits, then accepts a topic, shows a reactive NPC line, and allows at most two player picks before leaving.
  2. Every player topic roll applies deltas to both parties' directed meters and mood, shows feedback after each turn, and re-derives the five relationship types.
  3. When no exact response matches, the layered fallback produces a non-empty line; a headless test forces the fallback and verifies it.
  4. An NPC-initiated conversation in free time speaks its own topic with no deltas, offers 2–3 filtered replies, resolves the player's reply with the player as initiator, applies the final deltas, and ends after that one reply.
  5. No NPC-initiated conversation starts outside free time or while a conversation is open; the gate is a condition/callable, not a hardcoded state check.
  6. The dialogue overlay is a semi-transparent bottom panel over the visible world, with speaker name and numbered choices; portrait slots exist but are not rendered with art.
  7. Main Menu, Load Game, Options, Mods Menu, and Pause Menu scenes are reachable and routed through GameManager; New Game starts the default debug day directly.
  8. Named slots can be created (from the pause overlay), loaded, and deleted from the Load Game screen; F5/F9 still work; a reload restores day/state/meters/positions with template linkage.
  9. Volume, resolution, chunk settings, and language display are present in Options; changes apply immediately; the feedback toggle is absent; English is shown as current with a disabled selector.
  10. Mods can be enabled/disabled from the Mods Menu, flags persist in settings, both `res://mods/` and `user://mods/` are scanned, and changes take effect on next launch.
  11. ~40–60 topics and ~15–20 traits exist as `.tres` with modding registration; duplicate IDs are rejected add-only.
  12. NPCs seek friends/love interests and avoid enemies in free time based on directed meters; interest/mood goals still work.
  13. One integration harness covers all of the above; v1's three harnesses still pass; a RED/GREEN proof is recorded for a core conversation check.

## Out of Scope

- Functional New Game wizard (map/NPC-count/character selection); character creation; map editor.
- Calendar and weekend/season break choice pop-ups.
- Full academic system; expanded stats.
- Additional languages; audio polish.
- Performance tuning beyond ~4 NPCs; disk streaming of far chunks.
- Relationship-feedback UI toggle.
- Portrait art implementation (layout slots only).
- Network/HTTP endpoints (none; game is local).

## Further Notes

- Follows the design in `doc/idea-v2-brainstorming.md` (Approach A) and decisions in `doc/idea-v2-decisions.md`, including the four builder-check resolutions (layered response fallback; NPC-initiated reply contract; responder's relationship type keys a response; dual mod roots with settings-based enable/disable).
- Exact resolution presets, trait names/costs, schema field defaults, `Conversation` method signatures, menu styling, and test counts are builder decisions.
- The spec is published to the project issue tracker with the `ready-for-agent` label; no additional triage needed.
