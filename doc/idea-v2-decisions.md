# Project Renai v2 — Decisions

Source context: `doc/idea-v0.md` (original concept), `doc/idea-v1-final.md` (v1 snapshot), `doc/idea-v2.md` (goal + requirements), and the brainstorming sessions recorded in `doc/idea-v2-brainstorming.md`.

## Overall direction

- **Approach A (chosen):** conversation depth is the v2 headline feature, with a slim player-facing shell and content expansion folded in. Approach B (menu shell first) and C (content only) were rejected: B delays the thing that makes the game distinctive, C leaves no way for a player to reach the content.
- **Build approach A (chosen in the design session):** pure `Conversation` RefCounted helper + thin `Game.gd` wiring, extending `DialogueFilter`/`DialogueResolver`. Rejected: conversation state machine inside `Game.gd` (bloats an already ~890-line script, untestable) and a separate `Conversation.tscn` subsystem (per-interaction lifecycle unnecessary for one conversation at a time).
- **Deferred to v3:** calendar/break screens, character/map creation tools and map editor, full academics, additional languages, audio polish, performance tuning beyond ~4 NPCs, disk streaming of far chunks.
- **Language:** v2 stays GDScript (v1 shipped entirely in GDScript; no C# migration in v2).
- **Roster:** keep ~4 NPCs. Content and conversations are the focus; chunking stays latent on the 1×1 debug map.

## Conversation system

- **Length:** 2 exchanges max for player-initiated conversations. Exact sequence: greeting → player topic → NPC response → optional second topic + response → leave. The greeting is not counted as an exchange; each player pick gets its own roll.
- **Greeting:** authored greeting `.tres` resources. Variation factors (all four): relationship type, mood, period/time of day, and traits/interests.
- **Roll cadence:** one stat check per chosen topic, reusing the existing `DialogueResolver`.
- **Responses:** separate `.tres` response resources keyed by topic id, success/failure, and relationship band. The band is the **five derived relationship types** from `DialogueResolver.relationship_type()` (Stranger/Acquaintance/Friend/Enemy/Lover), not numeric meter buckets.
- **Response contract:** a `DialogueResponse` carries its **own roll fields** (`checked_stat`, `difficulty`, success/failure deltas). With roll fields populated it resolves as a normal topic+roll (player reply to an NPC); empty roll fields make it a line-only spoken reaction. It does not reference a separate `DialogueTopic`.
- **Three distinct resource types (chosen):** `DialogueGreeting`, `DialogueTopic` (existing), and `DialogueResponse`, in three `ModLoader` buckets (`TYPE_GREETING`, `TYPE_DIALOGUE`, `TYPE_RESPONSE`). Rejected: one type with a `kind` field, or fields added to `DialogueTopic`.
- **Meter feedback:** shown after each turn (existing feedback panel).
- **UI:** full-screen *overlay*, not a full art backdrop. The school world stays visible behind a semi-transparent bottom dialogue box with speaker name, line, and numbered choices stacked below. Reserved transparent portrait slots for both speakers (speaker left, listener right) are laid out but **not implemented in v2**. Replaced the small centered `DialoguePoolUI` for conversations.
- **NPC-initiated conversations — unique flow:**
  - NPC opens by talking about one of its own chosen topics (v1's initiator behavior, spoken as its opening line), then the player chooses a response.
  - Player response options: **fixed 2–3**, filtered by traits, mood, and other modifiers.
  - The player's response is a **normal topic + roll** using its own roll fields; its deltas are the final affection/mood change.
  - Length: **one player response, then end**.
  - Player input is **locked** during the reply, same as player-initiated.
  - Timing: **free time only right now**, but implemented via a condition/callable rather than a hardcoded state check, so future cases (a player and an NPC both skipping class) can be added without restructuring.

## Content

- **Large expansion:** ~40–60 dialogue topics total (greetings, player topics, responses) and ~15–20 new traits across categories.
- Trait/interest/dislike tags feed greeting variation, response filtering, and NPC goals.

## Menus and screens (v2 scope)

- **In scope:** Main Menu, Load Game, Options, Mods Menu, and an in-game Pause Menu. Separate scenes per screen, routed through `GameManager.change_scene()`.
- **Out of scope:** New Game flow (map / NPC-count / character selection). The Main Menu's **New Game** button starts the **default debug day directly**, using `GameManager.start_fresh_day()` — the same path DebugStart uses.
- **Entry point:** `MainMenu.tscn` becomes `run/main_scene`; `DebugStart.tscn` is kept as a developer shortcut.
- **Save/Load UI:** full naming UI — create a named slot from the **current live game state**, load, and delete. Reachable from the Main Menu **and** an in-game pause overlay, but **creating a named slot is pause-overlay only** (Main Menu has no live state). F5/F9 debug hotkeys remain.
- **Options screen settings:** Volume, Chunk settings (tier radii/tick rates), Language display, Resolution.
  - **Settings store:** a `SettingsManager` autoload backed by a `ConfigFile` at `user://settings.cfg`.
  - All settings changes **apply immediately** (showing a restart notice where the engine requires it).
  - **Resolution:** windowed presets + fullscreen toggle (exact presets left to builder).
  - **Language:** show "English" as the current setting with a disabled selector; do not claim unimplemented languages.
  - **Relationship feedback toggle is deliberately NOT in Options** — it remains a save-only/debug flag with a runtime API.
- **Mods Menu:** list installed/enabled mods with an enable/disable toggle that writes/removes the `.disabled` marker. Changes take effect **on next launch** (restart-required notice; no live rescan).
- **Pause overlay:** opened with Escape **only when no conversation is open** (the conversation owns Escape while open).

## NPC AI

- **Relationship-driven goals wired in v2:** seek friends/lovers and avoid enemies using directed meters to weight free-time destinations/goals (`NpcAi.relationship_candidates()`). No complex negotiation or multi-step planning.
- Existing interest/mood goals from v1 remain.

## Builder-check resolutions (final)

- **Response fallback:** layered — exact `(topic, outcome, relationship band)` → authored default response for the topic (blank band/outcome) → generic authored line → code-generated line. The authoring checklist requires one default response per topic; a headless test asserts the fallback fires when no exact match exists.
- **NPC-initiated reply contract:** the NPC's opening topic is spoken only — no roll, no deltas — so the player's reply produces the final change. Reply options are selected by `topic_id` + trait/mood/interest filters (outcome/band do not exist at selection time), with `DialogueResponse.text` serving as the **player's spoken line** in this flow (role inversion). The reply roll uses the **player as initiator**, NPC as target.
- **Response keying party:** the 5-type relationship band is derived for the **responder toward the speaker** (for player-initiated: the NPC's meter toward the player), since that is what the spoken line expresses.
- **Mods Menu deployment:** support both project-local and exported builds. Bundled base mods stay in `res://mods/`; an additional `user://mods/` scan root is added. Enable/disable flags are written to `user://settings.cfg` (not `res://` `.disabled` markers), so the menu works in a read-only export. Changes take effect on next launch.

## to-spec decisions (v2)
- **Testing seam:** one persistent integration harness at the highest seam (menus/New Game → conversation → menus/settings/mods → save/reopen → relationship goal), reusing v1's marker-based pass/fail pattern; v1 harnesses re-run as regressions.
- **Issue tracker:** v2 spec published as a GitHub issue with `ready-for-agent` label.
- **User stories depth:** extensive — 42 stories covering conversations, overlay, content, menus, settings, saves, mods, NPC goals, verification.
- **Builder details:** exact resolution presets, trait names/costs, schema defaults, Conversation method signatures, menu styling, and test counts remain builder choices; spec states the contracts only.

## to-tickets decisions (v2)
- **Ticket files:** stored in `doc/tickets/`, named `<NN>-<short-description>.md`, continuing numbering from v1 (021–033).
- **Ticket count:** 13 tickets after merging the proposed traits/content and bulk-content tickets into one (022), per user request.
- **Granularity/blocking edges:** user-approved as proposed; each ticket depends only on genuine gates. SettingsManager (025) has no blockers; relationship goals (032) gated only by content (022); integration harness (033) gated by all six feature tickets.
- **GitHub issues:** 13 issues created (#23–#35) as sub-issues of spec #22 with `ready-for-agent` labels and native blocked-by edges. Mapping: 021→#23, 022→#25, 023→#28, 024→#29, 025→#24, 026→#30, 027→#31, 028→#33, 029→#26, 030→#27, 031→#34, 032→#32, 033→#35.

## Deferred unknowns (left to builder/plan)

- Exact schema fields/defaults for greetings and responses (esp. greeting weight and response roll-field defaults).
- Exact `Conversation` method signatures and phase enum names; whether mid-conversation state is saved (assumption: saves happen between turns).
- Which windowed resolution presets and ConfigFile keys.
- How "period/time of day" is derived (existing `TimeManager` period vs. clock hour).
- Exact shape of the free-time gating callable for NPC initiation.
- Menu visual styling, placeholder portrait visuals, trait names/costs, topic distribution, test counts.
- Any C# migration (explicitly out of v2).

## Non-goals for v2

- Character creation, map editor, and the functional New Game wizard.
- Calendar, weekend/season break choice pop-ups.
- Full academic system or expanded stats.
- Additional languages and audio polish.
- Performance tuning beyond ~4 NPCs; disk streaming of far chunks.
- Relationship-feedback UI toggle.
- Portrait art implementation (layout slots only).
