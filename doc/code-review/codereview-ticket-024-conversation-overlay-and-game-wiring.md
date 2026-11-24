# Code Review: ticket/024-conversation-overlay-and-game-wiring vs master

- **Branch:** `ticket/024-conversation-overlay-and-game-wiring` (commit `3275952`, reviewed as `git diff HEAD~1..HEAD`)
- **Base:** `master` (merge-base: `240e37fbda32755705901dfcb8ea9fceafc944ab`)
- **Changed files:** 17
- **Findings:** 9 (Critical: 0, High: 0, Medium: 4, Low: 5) — merged from two independent review passes; the two High findings found by the second pass were already fixed in follow-up commit `9d0f660` and are not re-listed.
- **Verification at review time:** 024 harness 36/36 before fixes, 39/39 after; regressions 018 42/42, 019 60/60, 020 58/58, 021 23/23, 022 23/23, 023 35/35.

## Findings

### 1. [Medium][Bug] NPC→player feedback labels were swapped
- **Location:** `scripts/Game.gd:482` (reviewed commit; `_show_conversation_feedback` passed session ids directly)
- **Evidence:** `Conversation.gd:263` calls `resolve_response(response, _target=player, _initiator=npc, ...)` while `Conversation.gd:317-323` reports the NPC as `get_initiator_id()`. `DialogueResolver.gd:226-229` keys `before`/`after` by roll direction, so `InteractionFeedbackUI.gd:138-143` rendered the player's meter changes under the NPC's name. `ConversationUITest.gd` had no assertion on the labels.
- **Problem:** The feedback panel silently attributed the two parties' changes to the wrong names in every NPC-initiated reply.
- **Recommendation:** Swap the session ids when `Conversation.is_npc_initiated()` before calling `show_result()`, and assert the rendered labels in the harness.
- **Status:** fixed — `_show_conversation_feedback()` now swaps roll-direction ids; new harness check T37 asserts `You:` / NPC-name labels.

### 2. [Medium][Bug] 2–3 reply options only existed for 3 of 16 topics
- **Location:** `scripts/Game.gd:912` (reviewed commit; `choose_opening_topic(_topics_for_conversation)`)
- **Evidence:** `Conversation.gd:214-228` picks the opening from all eligible topics; `DialogueFilter.gd:326-345` requires a rollable response with matching `topic_id`; only `topic:ask_day` (3), `topic:talk_sports` (3) and `topic:compliment` (2) have such responses. `Conversation.gd:244-249` then collapses the rest to one generated line-only reply. The recorded T29 pass depended on the seeded opening topic happening to be one of the three.
- **Problem:** Most NPC-initiated talks broke the spec's fixed 2–3 reply contract with no diagnostic.
- **Recommendation:** Restrict the opening pool to topics with at least two authored rollable replies, using the live registry in `Game.gd`; add a test that forces an unsupported opening topic.
- **Status:** fixed — `Game._topics_with_replies()` filters the opening pool (documents the call in `doc/idea-v2-decisions.md`); new harness check T38 forces an unauthored topic and still gets 2–3 options.

### 3. [Low][Maintainability] Dead `seed_value` parameter on `_begin_npc_conversation`
- **Location:** `scripts/Game.gd:891` (reviewed commit)
- **Evidence:** The parameter was declared and passed by `_try_one_initiation()` but never used; the session seed came from `_next_conversation_seed(initiator_id)`. The harness passed `4242` while the real seed depended on a global conversation counter.
- **Problem:** A caller could believe it controlled determinism when it did not.
- **Recommendation:** Remove the parameter (or use it). Prefer removal so one seed owner remains.
- **Status:** fixed — `_begin_npc_conversation(initiator, initiator_id)` no longer takes a seed.

### 4. [Low][Maintainability] Duplicated `_conversation_npc` state
- **Location:** `scripts/Game.gd:93, 590, 744` (reviewed commit)
- **Evidence:** The field was assigned in both begin paths and cleared on close but never read; `_dialogue_target` is the close-path reference, so the same NPC received `set_conversation_busy(false)` twice.
- **Problem:** Two fields claimed the same role and produced a redundant unlock.
- **Recommendation:** Delete the field and its assignments.
- **Status:** fixed — field removed; `_dialogue_target` is the single reference.

### 5. [Low][Documentation] Stale phase-change comment contradicted the lock behavior
- **Location:** `scripts/Game.gd:1101` (reviewed commit; now `:1131`)
- **Evidence:** The comment said class/BREAK/DAYEND "must not inherit a conversation lock", but `_clear_active_initiations()` deliberately preserves `_conversation_locked_ids` while a conversation is open, matching `doc/idea-v2-decisions.md`.
- **Problem:** A future maintainer could "fix" the intentional preservation and unlock a conversation mid-turn.
- **Recommendation:** Reword to state that hold timers clear while open conversations keep their locks until `_close_conversation()`.
- **Status:** fixed — comment updated.

### 6. [Medium][Bug] Stale choice buttons remained in the tree for one frame
- **Location:** `scripts/ConversationUI.gd:180-186` (`_clear_buttons`)
- **Evidence:** Old buttons were only `queue_free()`d, so they stayed in `_choices_box` until end of frame while `show_line()` immediately installed new buttons. `_on_choice_pressed()` (`:188-192`) checks only `_is_open` (still true) and index bounds, so a second event in the same frame could apply a stale index to the new action list (e.g. greeting Continue immediately rolling a topic).
- **Problem:** A fast double input could skip the topic pool.
- **Recommendation:** `remove_child()` before `queue_free()` in `_clear_buttons()`.
- **Status:** fixed — stale buttons are detached synchronously.

### 7. [Medium][Testing] Mouse/`Button.pressed` path was never exercised
- **Location:** `tests/ConversationUITest.gd:321-327` (`_send_key_to`)
- **Evidence:** All interactions called `_unhandled_input` directly; no `Button.pressed` emission or mouse event existed in the harness. Headless Godot cannot route `parse_input_event()` to `_unhandled_input` in this project (v1 harness note), so `Button.pressed.emit()` is the practical seam.
- **Problem:** A regression in the mouse-click path promised by `ConversationUI.gd:12` would go undetected.
- **Recommendation:** Drive at least one transition through `Button.pressed`.
- **Status:** fixed — T13 now advances via `_press_first_choice()` emitting `pressed` on the first rendered button.

### 8. [Medium][Testing] NPC-initiated flow tests bypassed the production gate
- **Location:** `tests/ConversationUITest.gd:241` (direct `_try_one_initiation` call)
- **Evidence:** T23/T24 only asserted the `_initiations` signal count; T24 never asserted that the overlay opened with reply options when the injected gate fired.
- **Problem:** The real `_process` → gate → candidate-selection path was never proven to reach the reply UI.
- **Recommendation:** In the gate test, arrange one eligible outgoing initiator and the player as its target, then assert the reply UI after the gate fires.
- **Status:** fixed — T24b now asserts the gate-driven path reaches a 2–3 reply UI; the direct call remains only for deterministic flow checks.

### 9. [Low][Testing] T15 over-specified success
- **Location:** `tests/ConversationUITest.gd:131-144` (reviewed commit)
- **Evidence:** The check required all six familiarity/affection/mood fields to differ; an authored zero delta would fail it even though the interaction was valid.
- **Problem:** Brittle assertion coupled to current content values.
- **Recommendation:** Assert at least one non-zero delta per party from the resolver payload.
- **Status:** fixed — T15 now uses `result["deltas"]` and `_has_nonzero_delta()`.

### Caveat on the earlier T38 fix
The T38 test passed an unsupported topic array to `_try_one_initiation`, but the NPC→player branch intentionally ignores the caller's topic list and reads the supported pool from the registry. The check was relabelled to what it actually proves: "unsupported opening topics are replaced by reply-supported ones". The helper's genuine no-authored-reply fallback remains covered by ticket 023's T32.

## Evidence validation

All nine findings were re-checked against the working tree after fixes: the harness now reports 39/39 (`ALL_024_CHECKS_PASSED`), including new checks T37 (feedback labels), T38 (supported opening topics), and T24b (production gate path). No finding was retained without a file:line reference and concrete code/test evidence.
