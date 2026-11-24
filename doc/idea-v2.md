# Project Renai v2 — Goal and Requirements

Derived from `doc/idea-v0.md` (original concept), `doc/idea-v1-final.md` (v1 snapshot), and the decisions in `doc/idea-v2-decisions.md`.

## Goal

Turn the v1 debug slice into something a player can actually play and stay with: **make conversations feel like conversations** — an NPC greets you, you speak, they react differently depending on how the exchange went and how your characters relate — and wrap that in a **minimal player-facing shell** (Main Menu, Load Game, Options, Mods Menu) with **enough authored content** (traits and topics) that the social simulation has room to express itself.

v2 does not build the full game from `idea-v0.md`. It deepens the thing that makes Project Renai distinctive (romance + interacting traits) and adds just enough interface and content to reach it. Calendar/break screens, creation tools, full academics, localization, audio polish, and large-roster performance work are v3 and later.

Approach: **A — conversation depth first**, with a slim menu shell and content folded in. v1's data-first, pair-agnostic architecture is preserved and extended, not replaced. The project remains Godot 4.2 / Windows / GDScript, with ~4 NPCs on the shipped debug map.

## Requirements

### 1. Conversation system (headline)

1.1 **Player-initiated conversation, max 2 exchanges:** approach an NPC, press E. The NPC opens with an authored greeting `.tres`; the player picks from a 3–5 topic pool; the NPC responds with an authored response `.tres`; an optional follow-up exchange may occur; then the conversation ends.

1.2 **Greeting variation:** the greeting resource is chosen/conditioned by relationship type, mood, period/time of day, and traits/interests. Greetings are `.tres` resources, moddable like topics.

1.3 **One roll per chosen topic:** each topic the player selects resolves through the existing `DialogueResolver` (stat + familiarity + random vs. topic difficulty), reusing all existing deltas, recipient modifiers, margin scaling, and relationship derivation.

1.4 **Responses are authored data:** separate `.tres` response resources keyed by topic id, success/failure, and relationship band. They are loaded via the registry and moddable.

1.5 **Meter feedback after each turn:** the existing feedback panel shows affection/familiarity/mood changes and any relationship-type change immediately after each topic, honoring the persisted show/hide flag.

1.6 **UI — full-screen overlay:** the dialogue box covers the bottom of the screen as a semi-transparent overlay; **the school world stays visible behind it**. It shows the speaker name, the spoken line, and numbered choices stacked below. Reserved transparent portrait slots for both speakers (speaker left, listener right) are part of the layout but **not implemented in v2**.

1.7 **NPC-initiated conversations (unique shape):** an NPC opens by talking about one of its own chosen topics (v1's initiator behavior), then the player picks from a **fixed 2–3** response options filtered by traits, mood, and other modifiers. The player's response is a normal topic + roll; its deltas are the final affection/mood change. The exchange ends after that one player response.

1.8 **Initiation timing:** NPC-initiated conversations are gated to free time **for now**, but the gate must be a condition/callable rather than a hardcoded state check, so future cases (a player and an NPC both skipping class) can be added without restructuring.

### 2. Content expansion

2.1 **~40–60 dialogue topics total**, covering greetings, player topics, and response lines across social and romantic situations.

2.2 **~15–20 new traits** across skills, interests, dislikes, and personality, with point costs and tags, feeding greeting variation, response filtering, and NPC goals.

2.3 All new content is authored as `.tres` resources in `resources/` and registered as base content or via the sample mod; no content is hardcoded in scripts.

### 3. Player-facing shell

3.1 **Main Menu** with New Game, Load Game, Options, Mods Menu, and Quit.

3.2 **New Game starts the default debug day directly** — shipped map, shipped player template, existing save-option defaults. No map/NPC-count/character-selection wizard in v2.

3.3 **Load Game screen** with a **full naming UI**: create a named slot from the current live game state, load a slot, delete a slot. Reachable from the Main Menu **and** from an in-game pause overlay; F5/F9 debug hotkeys remain.

3.4 **Options screen** exposing: Volume, Chunk settings (tier radii and tick rates from `ChunkConfig`), Language display ("English" as current with a disabled selector), and Resolution (windowed presets + fullscreen toggle). The relationship-feedback toggle is **not** added to Options; it remains a save-only/debug flag with a runtime API.

3.5 **Mods Menu** listing installed/enabled mods with an enable/disable toggle that writes/removes the `.disabled` marker. Toggling shows a restart-required message; the change takes effect on next launch (no live rescan).

### 4. NPC AI

4.1 Wire `NpcAi.relationship_candidates()` so directed familiarity/affection meters weight free-time goals: NPCs seek friends/love interests and avoid enemies. Interest- and mood-based goals from v1 remain. No complex negotiation or multi-step planning.

### 5. Verification

5.1 Extend the persistent `tests/` harness pattern from v1 (headless Godot, marker-based pass/fail) to cover conversation flow (greeting, topic roll, response selection, both meter sides, 2-exchange limit, NPC-initiated single-response shape, free-time gating), the menu screens and their save/options/mods operations, and relationship-driven goal selection.

5.2 Re-run the v1 day-loop, chunk-renderer, and chunk-manager harnesses as regressions; v1 acceptance criteria must still pass.

## Assumptions

- v2 builds on the shipped v1 architecture unchanged: resource schemas and registries, `TimeManager` state machine, `DialogueFilter`/`DialogueResolver`, `NpcInstance` shape, `ModLoader`, `SaveManager`, `ChunkManager`/`ChunkConfig`, `Npc`, `NpcAi`, and the `tests/` harness pattern.
- The game still runs with ~4 NPCs on the 1×1-chunk debug map; chunk loading stays exercised only by synthetic tests.
- "Simple but cute" UI style from `idea-v0.md` still applies; v1 has no art assets, so the overlay uses generated shapes/colors and text.
- All dialogue content is authored in the Godot editor as `.tres` files; the plan supplies a schema and checklist, not the authoring.
- Save format stays Godot Resource `.tres` slots in `user://`; the full naming UI uses the existing sanitization and slot APIs.
- English remains the only language; the Options entry only displays it.
- Volume controls affect the existing AudioManager; resolution changes use Godot display settings.
- The feedback flag remains persisted in `SaveGame` and controllable through its existing runtime API.
- New Game, menus, and the pause overlay are reachable without changing `run/main_scene`: the project still launches into a menu-driven flow rather than v1's direct DebugStart path. (Exact scene wiring is a builder decision.)

## Unknowns / deferred to builder or plan

- Exact schema fields for greeting and response resources and for any conversation-session state.
- Whether an in-progress conversation is saved (assumption: saves happen between turns; mid-conversation state is not persisted).
- Exact trait names, point costs, and tag vocabulary for the 15–20 new traits.
- Exact assignment of the ~40–60 topics across greetings, player topics, and responses.
- Which windowed resolution presets to offer.
- How "period/time of day" is derived for greeting variation (existing `TimeManager` period vs. clock hour).
- Exact shape of the free-time gating callable for NPC initiation.
- Exact layout/styling of the four menu screens and the pause overlay; portrait slot visuals are deferred, not implemented.
- Whether Options changes (volume/chunk/resolution) apply immediately or on restart.
- How the Mods Menu restart-required notice is presented.
- Specific acceptance thresholds and counts for the new headless tests.
- Any C# migration (explicitly out of v2).

## Non-goals for v2

- Character creation, map editor, and the functional New Game wizard.
- Calendar, weekend/season break choice pop-ups.
- Full academic system or expanded stats.
- Additional languages and audio polish.
- Performance tuning beyond ~4 NPCs; disk streaming of far chunks.
- Relationship-feedback UI toggle.
- Portrait art implementation (layout slots only).
