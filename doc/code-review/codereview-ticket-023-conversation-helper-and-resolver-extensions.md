# Code Review: Ticket 023 (conversation helper + filter/resolver extensions)

- **Branch:** `ticket/021-dialogue-greeting-response-schemas`
- **Base:** `master` (merge-base `240e37fbda32755705901dfcb8ea9fceafc944ab`)
- **Review scope:** uncommitted ticket-023 working-tree changes (5 modified tracked files + 5 new files), since ticket 023 is not yet committed. Base-branch diff was not used because it would fold in already-shipped 021/022 work.
- **Changed files:** 10
- **Findings:** 3 (Critical: 0, High: 0, Medium: 1, Low: 2)
- **Verification evidence:** `run_conversation_helper_tests.ps1` 32/32 PASS; regressions 018 41/41, 019 60/60, 020 58/58, 021 23/23, 022 23/23; RED/GREEN proof on `MAX_TURNS` (29/3 RED → 32/0 GREEN).

## Findings

### 1. [Medium][Bug] Line-only responses masquerade as failed rolls in the existing feedback panel

- **Location:** `scripts/DialogueResolver.gd:257-286` (payload), `scripts/InteractionFeedbackUI.gd:112-129` (consumer)
- **Evidence:** `_line_only_result()` returns `"success": false` with `checked_stat: ""`, `die: 0`, `roll: 0`, `difficulty: 0`. `InteractionFeedbackUI._display()` reads `bool(result.get("success", false))` and sets `_title.text = "Success!" if success else "Not quite..."`, then renders a roll line (`no stat 0 + fam 0 + die 0 = 0 vs 0`). Authored topic-default responses are line-only (ticket 022: one per topic), so the normal fallback path will show "Not quite..." with a bogus zero roll whenever ticket 024 wires feedback after each response.
- **Problem:** A neutral spoken reaction is presented to the player as a failed stat check.
- **Recommendation:** Add an explicit `"show_feedback": false` (or keep `success` absent) to the line-only payload in `_line_only_result()`, and have ticket 024 skip `InteractionFeedbackUI.show_result()` when `result.get("line_only", false)` is true. Add a harness assertion that the line-only payload carries the suppress flag.

### 2. [Low][Architecture] An empty NPC-initiated reply pool leaves the helper in TOPIC with no way to choose

- **Location:** `scripts/DialogueFilter.gd:337-345`, `scripts/Conversation.gd:230-237`, `scripts/Conversation.gd:243-248`
- **Evidence:** `build_reply_pool()` returns `[]` when no eligible rollable replies exist for the opening `topic_id`. `Conversation.build_reply_pool()` forwards that unchanged and stays in `Phase.TOPIC`; `choose_reply()` only advances to `DONE` when given a non-null response. A mod-added opening topic with no authored replies therefore leaves an open conversation with zero choices unless ticket 024 happens to call `leave()`. The spec's accepted shape is "fixed 2–3 reply options" and "a conversation never dead-ends".
- **Problem:** The helper exposes a stuck state instead of a graceful no-choice outcome.
- **Recommendation:** Either return one generated line-only reply option (mirroring `DialogueFilter.select_greeting`'s generated fallback) or add an explicit `decline()` method that records a no-change outcome and sets `DONE`. Add a headless check for the zero-authored-replies case.

### 3. [Low][Testing] Layered response fallback is only asserted at the filter seam, not through `Conversation.select_response()`

- **Location:** `tests/ConversationHelperTest.gd:...` (`_check_response_fallbacks` and `_check_relationship_band`)
- **Evidence:** T18–T21 call `DialogueFilter.select_response()` directly; only the `exact` layer is exercised through `Conversation.select_response()` (T26). The integration path that ticket 024 will actually call — `choose_topic()` → roll outcome → `select_response()` → `resolve_response()` for topic-default / partial / generic / generated lines — is not asserted end to end.
- **Problem:** A regression in how `Conversation` forwards `outcome`/`band`/`topics` could leave a layer untested while all filter-only checks still pass.
- **Recommendation:** Add two conversation-level checks: one where only a topic-default line-only response exists (assert `fallback == "topic_default"` and `line_only == true` from `get_last_response()`), and one with no responses at all (assert the generated line and empty deltas).

## Non-findings / evidence-validator notes

- The four additive eligibility fields on `DialogueResponse` (`min_mood`, `max_mood`, `required_traits`, `required_interests`) are intentional and documented in `doc/idea-v2-decisions.md`; the 021 round-trip harness still passes 23/23.
- `resolve_response()` sourcing recipient modifiers from the keyed `DialogueTopic` is an explicit decision reconciling ticket 023 wording with the 021 schema; T23 asserts the +5 modifier transfer.
- No claims were kept that lack a `file:line` reference and a concrete code/test observation.
