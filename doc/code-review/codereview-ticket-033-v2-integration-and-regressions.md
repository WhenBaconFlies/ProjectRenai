# Code Review: ticket/033-v2-integration-and-regressions vs master

- **Branch:** `ticket/033-v2-integration-and-regressions` (`757a964`)
- **Base:** `master` (`79f8f26`, merge-base `79f8f26`)
- **Changed files:** 6 (4 new harness files, 2 docs). Production code untouched.
- **Findings:** 12 (Critical: 0, High: 2, Medium: 6, Low: 4)
- **Evidence audit:** PASS — every claim below cites file:line and production-code or test-output evidence. Vague/unsourced claims were dropped.

## Findings

### 1. [High][Test-quality] T21 does not exercise the initiation gate it claims to test
- **Location:** `tests/V2IntegrationTest.gd:268-273`
- **Evidence:** `Game._try_npc_initiations()` (`scripts/Game.gd:898-942`) never calls `_npc_gate_open()` or reads `npc_initiation_enabled`; both are consulted only in `Game._process()` (`scripts/Game.gd:1293-1298`). T21 calls the inner method directly, so `not ui.is_open()` passes independently of the injected callable. Spec AC5 (`doc/idea-v2-spec.md:119`) is uncovered.
- **Problem:** the check can pass with a permanently broken gate, and its comment ("blocks the production path") is false.
- **Recommendation:** assert `_game.call("_npc_gate_open") == false` after injection, then drive `Game._process(delta)` with a sub-interval timer so the real loop reaches the gate; assert no overlay.

### 2. [High][Test-quality] Harness cleanup and quit are skipped on abnormal abort; launcher can hang forever
- **Location:** `tests/V2IntegrationTest.gd:896-905`, `tests/run_v2_integration_tests.ps1:36-50`
- **Evidence:** `_finish()` is the only `quit()` path and is called only from three points in `_run()`. Several unguarded dereferences sit inside awaited sections (`tests/V2IntegrationTest.gd:365-366`, `:385`, `:437`, `:521-522`). An abort before `:57` leaves `user://v2_integration_settings.cfg` and slot `v2_integration` on disk and the headless process alive. This was observed during development: a script parse error left the console process running until it was killed after 300 s.
- **Problem:** a failed harness can wedge CI and leak fixtures.
- **Recommendation:** install an `_exit_tree()`/`NOTIFICATION_EXIT_TREE` cleanup guard that always restores the settings path, removes the slot and marks the event handled; add `Start-Process -PassThru` + `Wait-Process -Timeout` with kill-and-`V2_INTEGRATION_033_FAILED` fallback to the launcher.

### 3. [Medium][Test-quality] T14's fallback clause is tautological and does not force a fallback
- **Location:** `tests/V2IntegrationTest.gd:194-205`
- **Evidence:** `Conversation.select_response()` always writes `fallback` (`scripts/Conversation.gd:204`), and `DialogueFilter.select_response()` always returns one of `exact|topic_default|topic_partial|generic_authored|generated` (`scripts/DialogueFilter.gd:272-293`). A non-empty `fallback` is therefore true even for an exact match. Spec AC3 requires forcing the fallback (`doc/idea-v2-spec.md:117`).
- **Problem:** the check cannot detect a regression that makes every pick resolve as `exact`.
- **Recommendation:** assert the concrete layer is one of the four non-exact names under this fixture's fixed seed (the observed GREEN value is `topic_default`), or force a layer by temporarily removing exact responses from the registry.

### 4. [Medium][Test-quality] Spec AC5's "outside free time" and "while a conversation is open" halves are unexercised
- **Location:** `tests/V2IntegrationTest.gd:260-275`
- **Evidence:** T20 advances directly to `FREETIME1`; T21 only injects a callable (and per finding 1 via the wrong path). No PERIOD1 initiation attempt or open-conversation initiation attempt exists in the 56 checks, though `doc/idea-v2-spec.md:119` names both.
- **Problem:** a regression that opens talks in class or starts a second talk mid-conversation passes.
- **Recommendation:** add a PERIOD1 check using the default gate with the real `_process()` loop, and a check that driving `_process()` while `_dialogue_open` leaves the current conversation unchanged.

### 5. [Medium][Test-quality] T13 cannot detect wrong-but-valid relationship re-derivation
- **Location:** `tests/V2IntegrationTest.gd:181-192`
- **Evidence:** it asserts membership in the same five-element constant list `DialogueResolver.relationship_type()` is defined to return (`scripts/DialogueResolver.gd:306-327`), without comparing to the post-roll meters or the before snapshot. AC2 requires re-derivation (`doc/idea-v2-spec.md:116`).
- **Problem:** a stale or wrongly classified type still passes.
- **Recommendation:** compute the expected type from each party's `after` meter with the documented thresholds, accepting either `Lover` or `Friend` at ≥60/≥60 because of the mutual-romance gate, and compare.

### 6. [Medium][Test-quality] T55 omits two explicit AC11 requirements
- **Location:** `tests/V2IntegrationTest.gd:625-638`
- **Evidence:** the check asserts `traits.size() >= 15` and `40 <= dialogue_total <= 60`; the spec says ~15–20 traits and requires duplicate IDs rejected add-only (`doc/idea-v2-spec.md:125`). No trait upper bound or duplicate-registration attempt exists anywhere in the harness.
- **Problem:** an unbounded trait explosion or broken add-only rule passes this ticket.
- **Recommendation:** add `traits.size() <= 20` and a duplicate `Trait` id registration through `ModLoader.register_resource()` asserting `false` and that the original resource is unchanged.

### 7. [Medium][Test-quality] AC8's delete-from-Load-Game and F5/F9 hotkeys are not asserted
- **Location:** `tests/V2IntegrationTest.gd:384-424`, `:650-652`
- **Evidence:** T32–T37 cover Save As, list and load; the only delete is `SaveManager.delete_slot()` called directly by `_remove_slot()` at setup/teardown. No F5/F9 action events are sent, though `Game._unhandled_input()` handles them at `scripts/Game.gd:447-453` and AC8 names both (`doc/idea-v2-spec.md:122`).
- **Problem:** a broken Delete button or disabled debug hotkeys pass this ticket.
- **Recommendation:** press the located row's `DeleteButton` twice from the embedded Load Game screen and assert the slot is gone; send `manual_save`/`manual_load` `InputEventAction`s to `Game._unhandled_input()` and assert the manual slot and scene-change seam.

### 8. [Medium][Documentation] RED/GREEN record claims a reactive-line mutation that was never made
- **Location:** `doc/idea-v2-decisions.md:226-227`, `doc/tickets/033-v2-integration-and-regressions.md:21`
- **Evidence:** `Conversation.MAX_TURNS` is referenced only by `can_pick_topic()` (`scripts/Conversation.gd:308`) and `_advance_after_response()` (`:412`). T14 has no dependency on it; the RED run's only behavioral failure was T17, plus the self-referential T56 count check.
- **Problem:** the proof record overstates what was demonstrated.
- **Recommendation:** reword to "two-pick limit (T17) + T56 count check"; do not claim a reactive-line mutation without performing one.

### 9. [Low][Test-quality] T53 asserts only absence of `seek:`, not enemy avoidance
- **Location:** `tests/V2IntegrationTest.gd:605-612`
- **Evidence:** `NpcAi.select_goal()` skips non-positive player weights before the `avoid:` branch (`scripts/NpcAi.gd:123-127`), so no `avoid:` goal is produced (also recorded at `doc/idea-v2-decisions.md:214`). The check ignores the chosen destination.
- **Problem:** a regression walking toward the enemy under another goal string passes.
- **Recommendation:** assert the destination is not the player's position and rename the label to the implemented exclusion semantics.

### 10. [Low][Test-quality] T41's `notice == null` clause can never fail
- **Location:** `tests/V2IntegrationTest.gd:495-499`
- **Evidence:** `scripts/Options.gd:7` documents that display changes need no notice, and no `RestartNotice` node is created by the real screen.
- **Problem:** dead assertion adds false confidence.
- **Recommendation:** assert that no *visible* restart notice exists, or drop the clause and keep the applied-value assertion.

### 11. [Low][Test-quality] "Feedback after each turn" is checked only after the first pick
- **Location:** `tests/V2IntegrationTest.gd:178-180` vs `:210-216`
- **Evidence:** the feedback panel is hidden only before the NPC-initiated talk; no assertion follows the second player pick.
- **Problem:** a regression that stops showing feedback on follow-up turns passes.
- **Recommendation:** hide the panel before the second pick and re-assert `is_open()` plus labels afterwards.

### 12. [Low][Determinism] T52/T54 accept on "any of N rolls" instead of a specified roll
- **Location:** `tests/V2IntegrationTest.gd:594-620`
- **Evidence:** `evaluate_goal()` increments `_eval_count` (`scripts/Npc.gd:291`) and the seeded RNG depends on it (`scripts/NpcAi.gd:148`); the checks loop 12/8 times and accept any hit. Adding a hangout or changing an instance-id hash can flip the result.
- **Problem:** goal assertions are brittle against unrelated content changes.
- **Recommendation:** pin `_eval_count`/`_seed_value` on the real `Npc` for one deterministic evaluation and assert that specific outcome.

## Focus areas with no defect found

- Launcher portability, log clearing, marker gating and raw-exit-code policy: `tests/run_v2_integration_tests.ps1:13-50` (only the timeout gap from finding 2).
- Deterministic clock, headless display short-circuit, and normal/failed-assertion fixture cleanup: `TimeManager.set_process(false)`, explicit `advance()`, `SettingsManager.gd:511-514`, and `V2IntegrationTest.gd:62-70,896-905`.
- T5/T6/T7/T9/T10/T11/T15/T16/T17/T18/T19, T22–T30, T31–T37, T39/T40/T42–T50 were checked against the corresponding production seams; no wrong-payload/key defects found.
- No dead helper code; `_first_diff` and DEBUG prints are used diagnostics; T56's self-referential count check is the explicitly deferred v1 convention (`doc/idea-v2-decisions.md:219`).
