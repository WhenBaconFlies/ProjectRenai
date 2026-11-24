# 023: Conversation helper + filter/resolver extensions

**What to build:** A pure `Conversation` (`RefCounted`) helper owning session state — phase (GREETING/TOPIC/RESPONSE/FOLLOWUP/DONE), turn count (max 2 player picks), initiator/target ids, seeded RNG — with no scene-tree or autoload references. Extend `DialogueFilter` with greeting selection and response selection (including the layered fallback: exact → topic default → generic authored → generated) and `DialogueResolver` with `resolve_response()` reusing the existing roll, margin scaling, recipient modifiers, dual-party meter/mood writes, and relationship derivation. The responder's derived relationship type toward the speaker keys a response. This ticket makes the full conversation rules verifiable headlessly, before any UI exists.

**Blocked by:** 021 (Dialogue greeting + response schemas + registry buckets), 022 (Traits + full dialogue content)

**Status:** done

- [x] `Conversation` is pure (no scene tree/autoload globals), seeded, and headless-instantiable
- [x] Phase flow supports greeting → topic → response → optional follow-up → done, with max 2 player picks
- [x] Greeting selection filters by all four factors with a safe any-eligible fallback
- [x] Response selection applies the layered fallback chain with no dead-end
- [x] `resolve_response()` resolves a response with roll fields and produces line-only outcomes when fields are empty
- [x] The 5-type relationship band is derived for the responder toward the speaker
- [x] Headless checks cover turn limits, fallbacks, both-party deltas, and seeded determinism

## Verification

- Persistent harness: `tests/ConversationHelperBootstrap.*`, `tests/ConversationHelperTest.gd`, `tests/run_conversation_helper_tests.ps1` — **35/35 checks pass** (`ALL_023_CHECKS_PASSED`, `CONVERSATION_023_OK`).
- Regressions re-run green: 018 (41/41), 019 (60/60), 020 (58/58), 021 (23/23), 022 (23/23).
- Builder decisions recorded in `doc/idea-v2-decisions.md` under "Ticket 023 — conversation helper + filter/resolver decisions".
- RED/GREEN proof (v2 acceptance 13): temporarily setting `Conversation.MAX_TURNS = 3` made T9/T10/T35 fail (32 passed / 3 failed, `CONVERSATION_023_FAILED`); restoring `MAX_TURNS = 2` returned 35/35 (`ALL_023_CHECKS_PASSED`).
- Code review: `doc/code-review/codereview-ticket-023-conversation-helper-and-resolver-extensions.md` (3 findings: 1 Medium, 2 Low). All three were applied: line-only payloads now carry `show_feedback: false` and `InteractionFeedbackUI.show_result()` skips them; an empty NPC-initiated reply pool now yields one generated line-only option; two conversation-level fallback checks were added.
