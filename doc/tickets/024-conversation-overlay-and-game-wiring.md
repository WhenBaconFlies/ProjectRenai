# 024: ConversationUI overlay + Game wiring

**What to build:** A `ConversationUI` Control overlay at the bottom of the screen — semi-transparent, showing speaker name and spoken line with stacked numbered choices, over the still-visible school world, with reserved (unimplemented) portrait slots for both speakers. Wire it into `Game.gd` with the pure `Conversation` helper: player-initiated flows show greeting → topic → reactive NPC line → optional second exchange → leave, with feedback after each turn. NPC-initiated conversations keep their unique shape: the NPC speaks its own topic with no deltas, the player gets 2–3 filtered reply options (response text as the player's line), the reply resolves with the player as initiator, then the talk ends. Input is locked during a conversation; the free-time gate is a condition/callable, not a hardcoded state check.

**Blocked by:** 023 (Conversation helper + filter/resolver extensions)

**Status:** done

- [x] A player-initiated talk shows a greeting, accepts a topic, shows a reactive NPC line, and allows at most two picks
- [x] The overlay is semi-transparent at the bottom with speaker name and choices; the world remains visible behind it
- [x] Portrait slots exist as placeholders but render no art
- [x] Feedback appears after each turn and the relationship type updates visibly
- [x] An NPC-initiated talk speaks its topic with no deltas, offers 2–3 filtered replies, resolves the player's reply, and ends
- [x] The player's input is locked for the duration of either conversation shape
- [x] NPC initiation only fires in free time via a callable/condition, with no crash when no candidates exist
- [x] The existing one-pick close path is fully replaced

## Verification

- Persistent harness: `tests/ConversationUIBootstrap.*`, `tests/ConversationUITest.gd`, `tests/run_conversation_ui_tests.ps1` — **38/38 checks pass** (`ALL_024_CHECKS_PASSED`, `CONVERSATION_024_OK`). It covers overlay layout/portrait placeholders, both conversation shapes, input lock, the callable gate, no-candidate safety, and the 2-pick limit at the real `Game.tscn` seam.
- Regressions re-run green: 018 (42/42), 019 (60/60), 020 (58/58), 021 (23/23), 022 (23/23), 023 (35/35). The 022 harness's response-count expectation was raised from 27 to 32 and its comment records ticket 024's five extra authored replies; the total stays at the spec's 60 dialogue resources.
- RED/GREEN proof: temporarily setting `Conversation.MAX_TURNS = 3` made T20 fail (36 passed / 2 failed, `CONVERSATION_024_FAILED`); restoring `MAX_TURNS = 2` returned 38/38 (`ALL_024_CHECKS_PASSED`).
- Builder decisions and user approvals recorded in `doc/idea-v2-decisions.md` under "Ticket 024 — conversation overlay + game wiring decisions".
- Code review: `doc/code-review/codereview-ticket-024-conversation-overlay-and-game-wiring.md` (5 findings: 2 Medium, 3 Low). All five were applied — swapped feedback labels, reply-supported opening-topic filter, dead seed parameter and duplicated NPC field removed, stale comment corrected — and the harness was extended to 38 checks (new T37/T38).
