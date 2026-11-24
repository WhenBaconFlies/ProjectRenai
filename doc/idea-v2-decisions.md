# Project Renai v2 — Decisions

Source context: `doc/idea-v0.md` (original concept), `doc/idea-v1-final.md` (what v1 shipped), and this brainstorming conversation.
Final restatement: `doc/idea-v2.md`.

## Overall direction

- **Approach A (chosen):** conversation depth is the v2 headline feature, with a slim player-facing shell and content expansion folded in. Approach B (menu shell first) and C (content only) were rejected: B delays the thing that makes the game distinctive, C leaves no way for a player to reach the content.
- **Deferred to v3:** calendar/break screens, character/map creation tools and map editor, full academics, additional languages, audio polish, performance tuning beyond ~4 NPCs, disk streaming of far chunks.
- **Language:** v2 stays GDScript (v1 shipped entirely in GDScript; no C# migration in v2).
- **Roster:** keep ~4 NPCs. Content and conversations are the focus; chunking stays latent on the 1×1 debug map.

## Conversation system

- **Length:** 2 exchanges max for player-initiated conversations (greeting → player topic → NPC response → optional follow-up → leave).
- **Greeting:** authored greeting `.tres` resources. Variation factors: relationship type, mood, period/time of day, and traits/interests.
- **Roll cadence:** one stat check per chosen topic, reusing the existing `DialogueResolver`.
- **Responses:** separate `.tres` response resources keyed by topic id, success/failure, and relationship band; moddable like topics.
- **Meter feedback:** shown after each turn (existing feedback panel).
- **UI:** full-screen *overlay*, not a full art backdrop. The school world stays visible behind a semi-transparent bottom dialogue box with speaker name, line, and 3–5 numbered choices stacked below. Reserved transparent portrait slots for both speakers (speaker left, listener right) are an option to implement later, not in v2.
- **NPC-initiated conversations — unique flow:**
  - NPC opens by talking about one of **its own chosen topics** (the usual initiator behavior from v1), then the player chooses a response.
  - Player response options: **fixed 2–3**, filtered by traits/mood/modifiers.
  - The player's response is a **normal topic + roll** using the existing resolver; its deltas are the final affection/mood change.
  - Length: **one player response, then end**.
  - Timing: **free time only right now**, but implemented so this is not a hard stopper for future cases (e.g., an NPC skipping class initiating with a player also skipping). A gating condition/callable is preferred over a hardcoded state check.

## Content

- **Large expansion:** ~40–60 dialogue topics total (greetings, player topics, responses) and ~15–20 new traits across categories.
- Trait/interest/dislike tags feed both greeting variation and response filtering.

## Menus and screens (v2 scope)

- **In scope:** Main Menu, Load Game, Options, Mods Menu.
- **Out of scope:** New Game flow (map / NPC-count / character selection). The Main Menu's **New Game** button starts the **default debug day directly**, using the shipped map and player template as v1 does today.
- **Save/Load UI:** full naming UI — create a named slot from the **current live game state**, load, and delete. Reachable from **both** the Main Menu and an **in-game pause overlay**; F5/F9 debug hotkeys remain.
- **Options screen settings:** Volume, Chunk settings (tier radii/tick rates), Language display, Resolution.
  - **Resolution:** windowed presets + fullscreen toggle (exact presets left to builder).
  - **Language:** show "English" as the current setting with a disabled selector; do not claim unimplemented languages.
  - **Relationship feedback toggle is deliberately NOT in Options** — it stays save-only/debug (runtime API + persisted flag).
- **Mods Menu:** list installed/enabled mods, with an enable/disable toggle that writes/removes the `.disabled` marker. Changes take effect **on next launch** (show a restart-required message; no live rescan).

## NPC AI

- **Relationship-driven goals wired in v2:** seek friends/lovers and avoid enemies using directed meters to weight free-time destinations/goals. No complex negotiation or multi-step planning.
- Existing `NpcAi.relationship_candidates()` hook is the seam; v1's interest/mood goals remain.

## Non-goals for v2

- Functional New Game wizard, character creation, map editor.
- Calendar and weekend/season break choice pop-ups.
- Full academic system.
- Additional languages, audio polish.
- Performance tuning beyond ~4 NPCs; disk streaming of far chunks.
- Portrait art/implementation (slots only).
- Relationship feedback UI toggle.

## Unknowns deferred to builder/plan

- Exact resource schema fields for greeting/response resources and the conversation-session state.
- Exact trait names, point costs, and tag vocabulary.
- Which windowed resolution presets to offer.
- How "period/time of day" is read for greeting variation.
- Exact shape of the free-time gating callable for NPC initiation.
- Whether an in-progress conversation is persisted on save (assumption: no; save between turns).
- Menu visual styling (carry forward "simple but cute" from `idea-v0.md`).
