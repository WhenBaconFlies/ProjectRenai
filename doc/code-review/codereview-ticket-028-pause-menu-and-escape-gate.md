# Code Review: ticket/028-pause-menu-and-escape-gate vs master

- **Branch:** `ticket/028-pause-menu-and-escape-gate`
- **Base:** `master` (merge-base: `ca0bdf22c9297a3fad301aea18b439bf9229143b`)
- **Reviewed commit:** `8b1a8a6` (`feat(028): add Pause Menu + Escape gate with whole-scene freeze`)
- **Changed files at review:** 11
- **Findings:** 3 (High: 1, Medium: 1, Low: 1) — all three fixed and re-verified
- **Verifier:** `code-reviewer` subagent; evidence audit (`evidence-validator`) PASS

## Findings

### 1. [High][Bug] Escape that cancels a conversation also opened the Pause Menu on the same event

- **Location:** `scripts/ConversationUI.gd:198-213`, `scripts/Game.gd:408-421`, `scripts/Game.gd:836-859`
- **Evidence:** Pre-fix `ConversationUI._unhandled_input()` emitted `cancelled` on `ui_cancel` but never marked the event handled; `Game._on_conversation_cancelled()` synchronously called `_close_conversation()`, which sets `_dialogue_open = false` (`Game.gd:859`). Godot 4.2 input propagates `_unhandled_input` child-first, so `Game._unhandled_input()` then saw `_dialogue_open == false` and called `open_pause()` on the same Escape. A repo-wide grep found no `set_input_as_handled` calls. The harness could not catch this because `tests/PauseMenuTest.gd` calls each handler separately (`_send_action`, line ~265).
- **Problem:** leaving a conversation with Escape instantly froze the day and opened the pause overlay, violating the ticket's "no overlap / Esc owned by exactly one" contract.
- **Recommendation (applied):** `ConversationUI._unhandled_input()` now calls `get_viewport().set_input_as_handled()` after emitting `cancelled` and after a digit-key choice; `Game.gd` additionally sets a one-event `_conversation_cancel_latch` in `_on_conversation_cancelled()` (cleared in the handler and deferred to end of frame) so a same-frame stale event cannot reach the pause gate. Added harness check **T34b** that delivers one `ui_cancel` event through `ui._unhandled_input` then `game._unhandled_input` and asserts neither pause nor pause overlay opens.
- **Verification:** `[028] PASS T34b: one Esc consumed by the conversation never opens pause`; 40/40 checks pass.

### 2. [Medium][Bug] Escape typed in the Save As field did not resume

- **Location:** `scripts/PauseMenu.gd:39-58`, `scenes/PauseMenu.tscn:70-76`
- **Evidence:** `SlotNameInput` is a `LineEdit`; Godot 4.2.1's `LineEdit::gui_input` handles `ui_cancel` by defocusing and calling `accept_event()`, so `Game._unhandled_input()` never saw that Escape while the user was naming a slot. The overlay hint (`PauseMenu.tscn:43`) promises "Esc resumes". The harness only injected `InputEventAction` directly into `_unhandled_input`, bypassing GUI input, so T26 passed despite the real interaction failing.
- **Problem:** first Escape while typing a slot name only defocused the field; a second press was required to resume.
- **Recommendation (applied):** `PauseMenu._input()` now handles `ui_cancel` before GUI processing when the overlay is open, calling `handle_cancel()` and `get_viewport().set_input_as_handled()`. Added harness check **T36b** that focuses the slot field, calls `pause._input()` with `ui_cancel`, and asserts the overlay resumes.
- **Verification:** `[028] PASS T36b: Esc resumes even while the slot-name field owns focus`.

### 3. [Low][Bug] Rejected slot text and status leaked into the next pause session

- **Location:** `scripts/PauseMenu.gd:53-62` (`open()`/`close()`)
- **Evidence:** `close()` only hid the overlay and `open()` cleared only `_status_label.text`; after T13/T14 (empty/reserved name rejected), `SlotNameInput.text` kept the rejected value.
- **Problem:** reopening pause showed a stale error state and stale input, which could cause an accidental repeated save.
- **Recommendation (applied):** `open()` now clears both `_slot_input.text` and `_status_label.text`. Added harness check **T36c**.
- **Verification:** `[028] PASS T36c: a new pause session clears rejected text and status`.

## Notes on an implementation mistake found while applying the review

The first fix attempt used `set_input_as_handled()` directly on `Node`; Godot 4.2 exposes it on `Viewport` only (`Viewport.set_input_as_handled()` / `Viewport.is_input_handled()`). That made both `ConversationUI.gd` and `PauseMenu.gd` fail to parse (`[028] FAIL T2: PauseMenu exists under PauseLayer with the expected seam`). Corrected to `get_viewport().set_input_as_handled()` in both scripts and reran.

## Evidence audit

| Claim | Evidence | Verdict |
|-------|----------|---------|
| Finding 1: same Escape closes talk and opens pause | `ConversationUI.gd:198-213` (no handled mark), `Game.gd:408-421`, `Game.gd:859` (`_dialogue_open = false`), child-first propagation documented in Godot 4.2 input docs | SUPPORTED |
| Finding 2: focused LineEdit swallows Escape | `PauseMenu.tscn:70-76` (LineEdit), Godot 4.2.1 `LineEdit::gui_input` `accept_event()` on `ui_cancel`, `PauseMenu.tscn:43` hint | SUPPORTED |
| Finding 3: stale text/status on reopen | `PauseMenu.gd` `open()` cleared only status at review time | SUPPORTED |
| Fixes verified | `ALL_028_CHECKS_PASSED` (40/40) and regressions 018–027 all OK after applying fixes | SUPPORTED |

**Verdict: PASS** — every finding has a file:line reference and a concrete code path; no vague claims retained.

## Final verification (after fixes)

- `tests/run_pause_menu_tests.ps1`: `ALL_028_CHECKS_PASSED`, `PAUSE_MENU_028_OK`, 40/40.
- Regressions: 018 (42/42), 019, 020, 021 (23/23), 022 (23/23), 023 (35/35), 024 (42/42), 025 (21/21), 026 (23/23), 027 (35/35) — all `_OK`.
- No source files were modified by the reviewer; fixes were applied by the implementer and re-verified.
