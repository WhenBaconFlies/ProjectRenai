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

## Ticket 021 — schema + registry decisions

Resolved the schema defaults deferred below; these are the contracts ticket 021 builds and later tickets consume.

- **Approach:** extend the existing `DialogueTopic`/`ModLoader` patterns — two new typed `Resource` classes with `class_name`, two new `ModLoader` buckets, and authored base `.tres` samples. No `DialogueFilter`/`DialogueResolver`/`Game.gd` changes in this ticket (they belong to 023/024).
- **`DialogueGreeting` fields (typed):** `id`, `text`; eligibility as `relationship_types: PackedStringArray` (empty = any; values = the five `DialogueResolver` type names), `min_mood: int = 0` / `max_mood: int = 100` (0/100 = no gate), `periods: PackedStringArray` of `TimeManager` state names (empty = any), `required_traits` / `required_interests: PackedStringArray` (empty = no gate), and `weight: float = 1.0` for a seeded weighted pick (authored now, consumed by 023). Rejected: named enum bands (lose the resolver's exact thresholds) and a single untyped Dictionary blob (not editor-readable).
- **Period vocabulary:** `TimeManager` state names (e.g. `PERIOD1`, `FREETIME1`), not clock-hour bands; deriving the current period stays with the later conversation tickets.
- **`DialogueResponse` key fields:** `outcomes: PackedStringArray` and `relationship_bands: PackedStringArray`, each allowing several values. An empty array is a wildcard for that field. This gives the fallback chain: exact (both arrays contain the values) → topic default (arrays empty, `topic_id` set) → generic authored line (arrays empty, `topic_id` empty) → code-generated line. Rejected: two single strings (less expressive) and `success: bool` + `is_default` (still needs a separate wildcard flag).
- **Line-only rule:** a `DialogueResponse` is a line-only reaction when `checked_stat` is empty — a deliberate *divergence* from `DialogueTopic`, where an empty `checked_stat` only removes the stat bonus while the roll and deltas still run (`DialogueResolver.gd:102-140`). Other roll fields may be authored but are ignored; expose `is_line_only()` and document it on the resource. Ticket 023 must call `is_line_only()` and skip resolution entirely for line-only responses. Rejected: a separate `line_only` bool (two sources of truth) and "all roll fields zero" (an intentional zero-delta roll becomes impossible to author).
- **`DialogueResponse` roll fields:** `checked_stat: String`, `difficulty: int`, and success/failure `affection`/`familiarity`/`mood` deltas as ints — the same field names as `DialogueTopic`, but owned by the response and deliberately independent of the keyed topic's values. Ticket 023 must **extend** `DialogueResolver` with a response-aware entry point (or a roll-fields provider): `resolve()` is statically typed to `DialogueTopic` (`DialogueResolver.gd:63`) and reads `recipient_modifiers` (`:79`), which `DialogueResponse` intentionally does not carry. Reusing `resolve()` unchanged is not possible.
- **Registry layout:** new buckets `TYPE_GREETING` and `TYPE_RESPONSE`; base content in `resources/dialogue/greetings/` and `resources/dialogue/responses/` via `BASE_GREETINGS_DIR` / `BASE_RESPONSES_DIR`; add-only duplicate-ID rules unchanged. One sample `.tres` of each type authored as base content proves editor creation, save, and round-trip.
- **Verification:** a dedicated headless harness (`tests/DialogueSchemaBootstrap.*`, `tests/DialogueSchemaTest.gd`, `tests/run_dialogue_schema_tests.ps1`) asserts field round-trips, `is_line_only()`, and registry add-only behaviour; the v1 harnesses re-run as regressions.

## Ticket 022 — content + base trait registration decisions

- **Base trait registration (user-approved):** `ModLoader` gains `BASE_TRAITS_DIR` (`res://resources/traits/`) and registers `Trait` resources into the existing `TYPE_TRAIT` bucket during `_register_base_content()`. All 24 traits (6 existing + 18 new) become registry-visible under the same add-only duplicate-ID rule as every other bucket. Character templates keep referencing trait `.tres` files through `ext_resource` exactly as in v1.
- **Counts (builder choice):** 18 new traits (24 total), 12 greetings (10 new), 16 player topics (14 new), 27 responses (25 new) = 55 dialogue resources, inside the spec's 40–60 range. Id namespaces stay `trait:*`, `greeting:*`, `topic:*`, `response:*`.
- **Default-response coverage (builder choice):** every one of the 16 topics gets one authored *line-only* default `DialogueResponse` (`topic_id` set, `outcomes`/`relationship_bands` empty). Alongside the existing generic authored line, 7 band/outcome-specific lines exercise the exact-match layer, so all four fallback layers have real data.
- **NPC-initiated reply content (review resolution):** three rollable replies (`response:ask_day_reply`, `response:talk_sports_reply`, `response:compliment_reply`) carry their own stat/difficulty/deltas with `topic_id` set and both key arrays empty, so ticket 023 can select them by topic at reply time and roll the player's line. They are deliberately distinct from the line-only topic defaults by `is_line_only()`.
- **Character templates unchanged:** new traits are authored and registry-visible but are not assigned to the five base templates in this ticket. Trait-factor greetings use tags already present on the default player/NPC pair (`academic`, `sports`, `active`), which keeps the v1 harnesses stable.
- **Smoke check (builder choice):** a dedicated headless harness (`tests/TraitsAndDialogueContent.*`, `tests/run_traits_and_dialogue_tests.ps1`) validates vocab, counts, default-response coverage, all four greeting factors, add-only registration, and the default player (`char:alex`) / NPC (`char:jordan`) Stranger/PERIOD1 pair; the v1 harnesses and 021 re-run as regressions.

## Ticket 023 — conversation helper + filter/resolver decisions

- **Approach:** a pure `Conversation` (`RefCounted`) helper plus read-only/seeded extensions to `DialogueFilter`/`DialogueResolver`. No scene-tree or autoload references in the new helper code. Ticket 024 passes the live `TimeManager` period string and the authored resource arrays explicitly.
- **Conversation API (builder choice):** `begin_player_initiated(...)` / `begin_npc_initiated(...)`, `choose_greeting()`, `build_topic_pool()`, `choose_topic()`, `select_response()`, `leave()`; the NPC-initiated shape adds `choose_opening_topic()`, `build_reply_pool()`, `choose_reply()`. One seeded RNG owned by the helper draws sub-seeds for every filter/resolver call, so a whole conversation is reproducible from one seed. Phases are `GREETING`/`TOPIC`/`RESPONSE`/`FOLLOWUP`/`DONE`; `turn` counts player topic picks (max 2, greeting not counted).
- **Recipient modifiers for responses:** ticket 023 asks `resolve_response()` to reuse recipient modifiers, but `DialogueResponse` deliberately has no `recipient_modifiers` field (021 decision, to avoid two sources of truth). Resolution therefore reads them from the response's keyed `DialogueTopic` when the caller supplies the topic array, falling back to no modifiers for generic lines. No duplicate field is added to `DialogueResponse`.
- **Response selection layers:** exact `(topic_id, outcome, band)` with both key arrays populated → topic default (`topic_id` set, both arrays empty) → partial topic match (`topic_id` set, one key array populated) → generic authored line (no `topic_id`, both arrays empty) → code-generated line. The first non-empty layer wins with a seeded pick inside it. Every layer returns a non-empty line, so a conversation never dead-ends.
- **Greeting selection:** filter by all four factors (relationship band, mood band, period, trait/interest keys); when none pass, fall back to a seeded weighted pick over *every* authored greeting with text (the safe any-eligible fallback); when no greetings exist at all, return a generated line. `weight <= 0` excludes a greeting while any positive-weight candidate exists.
- **NPC-initiated reply filtering:** `DialogueResponse` gains four optional additive eligibility fields (`min_mood`, `max_mood`, `required_traits`, `required_interests`) with wildcard defaults mirroring `DialogueGreeting`, consumed only by `DialogueFilter.build_reply_pool()` (keyed by `topic_id` plus these gates, 2–3 options). Existing authored replies are unaffected. The opening topic is spoken only (no roll/deltas); the reply rolls with the player as initiator and the NPC as target.
- **Line-only outcome:** `resolve_response()` checks `is_line_only()` first and returns a result with `line_only: true`, zeroed roll/delta fields and unchanged before/after snapshots so the feedback UI can consume it safely without applying a phantom roll.

## Ticket 024 — conversation overlay + game wiring decisions

- **Session ownership (builder call):** `Game.gd` owns one `Conversation` instance per interaction, created from the 023 helper. The UI owns no conversation state: `ConversationUI` renders a speaker name, a spoken line and a list of numbered choices, and emits `choice_selected(index)` / `cancelled`. `Game.gd` maps each choice index to a typed action (`topics`, `topic`, `reply`, `leave`) so the UI stays generic and headless-testable.
- **UI node (builder call):** a new `ConversationUI` Control replaces `DialoguePoolUI` under `DialogueLayer` in `Game.tscn`; the old one-pick `DialoguePoolUI.gd` script is removed. The panel is bottom-anchored and semi-transparent so the school world stays visible. Two transparent placeholder Panels (`SpeakerPortrait` left, `ListenerPortrait` right) are laid out but render no art. Number keys, mouse and Esc (leave) are accepted.
- **Turn choreography (builder call):** player-initiated = NPC greeting (Continue) → topic pool (3–5) → roll + feedback → NPC response line → Continue → optional second topic pool → final NPC line → Leave. NPC-initiated (player as target) = NPC's authored topic spoken with no roll/deltas (Continue) → 2–3 filtered reply choices → reply resolved with the player as roll initiator + feedback → the player's spoken reply line → Leave. Two player topic picks maximum; the greeting is not counted.
- **Double-resolution guard (builder call):** `Conversation.choose_topic()` and `Conversation.choose_reply()` are the only resolvers in the new flow. `Game.gd` no longer connects `dialogue_topic_selected` to a resolver; the signal is still emitted for v1 observers, and `dialogue_resolved` is emitted from the helper's result so both parties' feedback and the relationship-type change are shown after each turn.
- **NPC↔NPC vs player target (builder call):** an NPC-initiated interaction whose target is another NPC keeps v1's immediate resolution (no overlay, no reply wait) — there is no player to answer. Only an NPC→player initiation uses the ConversationUI reply shape. The timed initiation hold applies only to NPC↔NPC; an NPC→player talk holds its busy flags until the conversation closes.
- **Free-time gate (builder call):** a `Callable` property on `Game.gd` (defaulting to a zero-arg method that returns `TimeManager.is_free_time_state(TimeManager.get_state())`) is the sole gate for NPC initiation. `_process()` calls it instead of checking the state inline, so future "both skipping class" cases can inject another condition. A missing/invalid callable falls back to the default.
- **Input lock (builder call):** for the whole conversation the player's `set_input_locked(true)` and the `InteractionComponent` stay disabled, the NPC party stays `set_conversation_busy(true)`, and Esc is owned by the conversation (the pause menu in ticket 028 must check `Conversation.is_open()`/an `is_conversation_open()` seam first). All are released in one `_close_conversation()` path.
- **Seed and period (builder call):** the conversation seed is derived from the day number, a per-scene conversation sequence counter and the target id hash; the period string passed to 023 is `TimeManager.get_state_name()` at begin time. No wall-clock sampling inside the helper.
- **v1 regression harness (user-approved):** `DayLoopIntegrationTest`'s AC2 is updated to drive `ConversationUI` and assert the new multi-turn shape while keeping the same underlying checks (E → 3–5 choices → resolver result → both-party deltas → feedback). `ChunkManagerTest`'s UI node lookup is updated to the new node name. No legacy one-pick path stays in production.
- **Reply-option coverage (user-approved):** ticket 022 authored only one rollable `DialogueResponse` per reply topic, which made `build_reply_pool()` (keyed by `topic_id`) yield a single option instead of the spec's 2–3. Ticket 024 adds two extra authored rollable replies for `topic:ask_day` and `topic:talk_sports` and one for `topic:compliment` (5 extra, 8 total), keeping the 60-resource spec ceiling. The 023 filter contract and topic keying stay unchanged; the existing single generated line remains only the no-authored-reply last resort.
- **Reaction/reply response split (builder call):** the same registry is indexed twice per conversation — line-only responses feed the player-initiated reactive-line fallback, and all responses (including rollable replies) feed the NPC-initiated reply pool. Without this split a rollable reply keyed to `topic:ask_day` could be picked as the NPC's spoken reaction and fire a phantom second roll; 023's helper code is unchanged.
- **Opening-topic support filter (code-review fix 2):** an NPC-initiated talk only opens on a topic with at least two authored rollable replies, computed from the live registry in `Game._topics_with_replies()`. Without it, 13 of 16 topics would open and immediately collapse to the single generated reply, breaking the 2–3 option contract. The helper's `choose_opening_topic()` stays generic; the wiring supplies a supported pool.
- **Feedback labels (code-review fix 1):** `InteractionFeedbackUI` labels follow the resolver's roll direction, which flips for an NPC-initiated reply. `_show_conversation_feedback()` swaps the session ids for that shape so "You" is attached to the player's meter changes; a harness check asserts the labels.
- **Overlay input robustness (code-review fix 6):** `ConversationUI._clear_buttons()` detaches old buttons before `queue_free()`, so a same-frame second input cannot map a stale button index onto the newly installed choice actions. The harness exercises one choice through `Button.pressed` (mouse path) and one through `_unhandled_input` (number-key path).
- **Feedback panel placement (user-approved, editor pass):** the detailed feedback panel moved from bottom-centre to the **right-middle** of the screen (`InteractionFeedbackUI._build()` anchors) so it no longer covers the bottom conversation overlay. The panel still shows full before/after numbers for now; the user's final intent is a compact side indicator showing only the *trend* (e.g. `Fam +2 / Aff −1`), not exact values, so the player does not get a full grasp. That compact form is a later change, not v2 ticket 024.
- **NPC approach before talk (user-approved, editor pass):** an NPC-initiated talk with the player does not open the overlay from across the map. If the chosen NPC is farther than `Game.npc_talk_radius` (28 px, matching the interaction radius), it walks to a point beside the player first; the conversation opens on arrival. Busy flags are claimed during the approach so no other interaction double-books the pair, and a timeout (`Game.npc_approach_timeout_sec`, default 6 s) plus a player-moved-away retry cancels the approach cleanly. NPC↔NPC interactions are unchanged.

## Ticket 025 — SettingsManager decisions

- **Scope:** foundation only — `SettingsManager` autoload + `ConfigFile` at `user://settings.cfg`, typed getters/setters, startup + immediate application, corrupt-config fallback, and a headless round-trip harness. The Options screen (030) and ModLoader's settings-based enable/disable (029) are separate tickets; 025 only stores the flags they consume.
- **Config layout (builder choice):** sections `audio`, `display`, `chunk`, `language`, `mods`. Keys: `master_volume`, `resolution_width`, `resolution_height`, `fullscreen`, the nine `ChunkConfig` fields (radii, hysteresis, promotion duration, three tick rates, fallback pixel size, hide-far flag), `language`, and one boolean per mod id under `mods`.
- **Defaults (builder choice):** volume `0.8`; resolution `1280x720` windowed; language `English`; chunk values mirror `ChunkConfig`'s defaults; a mod id with no stored flag is treated as enabled. Resolution presets are `1280x720`, `1366x768`, `1920x1080` plus a fullscreen toggle, exposed as data for ticket 030.
- **Volume application (builder choice):** `AudioManager` is a v1 stub, so 025 adds a minimal typed master-volume API (`set_master_volume()` / `get_master_volume()`, 0..1 linear converted to dB via `AudioServer`) for `SettingsManager` to drive on load and on write. No other audio behavior is implemented.
- **Display application (builder choice):** `SettingsManager` writes width/height/fullscreen to `DisplayServer` when not headless; in headless runs the write is skipped (storage still round-trips) so harnesses never hit window APIs. Resolution/fullscreen changes are marked restart-required.
- **Chunk application:** `SettingsManager` builds a `ChunkConfig` from the stored fields and applies it with `ChunkManager.set_config()` on startup and on any chunk write, so tick-rate/radius changes take effect immediately without a restart notice.
- **Restart notice seam (builder choice):** 025 emits `restart_required(key)` and exposes `is_restart_required(key)`; ticket 030's Options screen presents the notice. No UI is added in 025.
- **Testability seam:** `set_config_path(path)` redirects the ConfigFile so the headless harness uses `user://settings_manager_test.cfg` and never touches the developer's real settings. `reload()` re-reads from disk and re-applies.
- **Robustness:** a missing, unparseable, or wrong-typed ConfigFile value falls back to the typed default with a warning log; `load()` errors never crash or overwrite the file until an explicit save.

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

- ~~Exact schema fields/defaults for greetings and responses (esp. greeting weight and response roll-field defaults).~~ Resolved in "Ticket 021 — schema + registry decisions" above.
- Exact `Conversation` method signatures and phase enum names; whether mid-conversation state is saved (assumption: saves happen between turns).
- ~~Which windowed resolution presets and ConfigFile keys.~~ Resolved in "Ticket 025 — SettingsManager decisions" above.
- ~~How "period/time of day" is derived (existing `TimeManager` period vs. clock hour).~~ Schema vocabulary resolved to `TimeManager` state names in "Ticket 021 — schema + registry decisions"; deriving the live period remains with the later conversation tickets.
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
