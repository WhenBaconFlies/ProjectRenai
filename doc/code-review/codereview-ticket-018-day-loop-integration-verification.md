# Code Review: ticket 018 (day-loop integration & acceptance verification)

- **Branch / state:** `master`, ticket-018 changes uncommitted (harness + decisions/ticket docs)
- **Base:** prior master HEAD `e6446b4` (ticket 017)
- **Changed files reviewed:** `tests/IntegrationBootstrap.gd`, `tests/IntegrationBootstrap.tscn`, `tests/DayLoopIntegrationTest.gd`, `tests/run_integration.ps1`, `doc/idea-v1-decisions.md`, `doc/tickets/018-day-loop-integration-verification.md`
- **Findings:** 8 (Critical: 0, High: 1, Medium: 5, Low: 2) — all triaged; 7 fixed, 1 ruling
- **Reviewer:** independent `code-reviewer` subagent + inline evidence audit
- **Evidence gate:** every finding below cites a `file:line` and a concrete code fact or command output

## Findings and disposition

### 1. [High][Bug] Autosave check could pass on a stale file from an earlier run
- **Location:** `tests/DayLoopIntegrationTest.gd:264-267` (before fix)
- **Evidence:** the check was `SaveManager.has_slot(SaveManager.AUTOSAVE_SLOT)`, and `SaveManager.has_slot()` is only `FileAccess.file_exists()` (`scripts/SaveManager.gd:132-133`). No slot deletion existed anywhere in `tests/`. A `user://saves/autosave.tres` left by any earlier run made AC1 pass even if DayEnd autosave regressed.
- **Problem:** false-pass on the first acceptance criterion.
- **Disposition: FIXED.** Added `_prepare_save_fixture()` (`tests/DayLoopIntegrationTest.gd:393`) which backs up any pre-existing autosave and deletes `autosave`, `integration`, `missing_template` before the day starts; `_restore_environment()` (`:404`) restores the backup or deletes the test-created slot. Verified: `user://saves/` contains only the user's pre-existing `autosave.tres` + `manual.tres` after a run, and `integration`/`missing_template` are gone.

### 2. [Medium][Bug] AC4 restore comparison omitted the persisted day snapshot
- **Location:** `tests/DayLoopIntegrationTest.gd:440-463` (after fix)
- **Evidence:** `_capture_state()` previously returned only day/state/feedback/player/npcs, but `SaveGame.day_snapshot` (`scripts/SaveGame.gd:33`) carries `phase_elapsed`, `attendance`, `grades`, `roster`, `player_id`, `player_absent` (`scripts/TimeManager.gd:343-353`).
- **Problem:** a regression restoring day/state but dropping grades/attendance/roster would pass AC4.
- **Disposition: FIXED.** Added `"day_snapshot": TimeManager.get_day_snapshot()` at `:460`. Initial run then failed AC4 because `phase_elapsed` is not bit-identical after a `.tres` round-trip; added a 0.01 tolerance for floats in `_value_equal()` (consistent with the existing Vector2 tolerance). Final run: AC4 PASS with the full snapshot compared.

### 3. [Medium][Bug] AC2 claim "both parties' meters and mood change" overclaimed the assertion
- **Location:** `tests/DayLoopIntegrationTest.gd:189-196` (after fix)
- **Evidence:** the old expression compared only initiator familiarity, target familiarity and initiator mood; the resolver result contains all six per-party fields (`scripts/DialogueResolver.gd:229-234`).
- **Problem:** dropping target mood or all affection deltas would still pass.
- **Disposition: FIXED.** Loop over both parties × {familiarity, affection, mood} and require all six to change; label renamed to "both parties' familiarity, affection and mood change". Verified PASS.

### 4. [Medium][Architecture] AC10 documentation check was effectively inert
- **Location:** `tests/DayLoopIntegrationTest.gd:574-614` (after fix)
- **Evidence:** old check used `text.count("##")`, and `scripts/Game.gd` alone has ~20 header `##` lines, so the branch always passed regardless of per-function comments.
- **Problem:** criterion 10 could pass with no function documentation at all.
- **Disposition: FIXED.** Now requires a script-level `##` header and counts functions whose preceding non-blank line is `##`; prints the measured coverage and requires ≥50%. Measured: `AC10 function doc coverage: 212/303 (69%)`. See ruling in §Rulings on why 100% is not required.

### 5. [Medium][Documentation] Decision doc contradicted the harness input strategy
- **Location:** `doc/idea-v1-decisions.md:325` (before fix)
- **Evidence:** it said E/number keys "use `Input.parse_input_event()`", while the harness calls the handlers directly via `node.call("_unhandled_input", event)` (`tests/DayLoopIntegrationTest.gd:_send_key_to`), and a later bullet already explained that `parse_input_event()` does not reach `_unhandled_input` headless.
- **Problem:** stale, self-contradictory design record.
- **Disposition: FIXED.** Line 325 now describes direct handler dispatch and cross-references the verification finding.

### 6. [Medium][Architecture] Launcher hardcoded a machine-specific Godot path
- **Location:** `tests/run_integration.ps1:12-31` (after fix)
- **Evidence:** the old launcher used only `$godot = 'D:\Godot\Godot_v4.2.1-stable_win64_console.exe'` and exited on any other machine.
- **Problem:** the permanent harness was not runnable as checked in outside this workstation.
- **Disposition: FIXED.** Added `param([string]$GodotPath = $env:GODOT_PATH)`, PATH discovery, then the documented default, with an actionable error message. Re-verified with the default path: `INTEGRATION_018_OK`.

### 7. [Low][Bug] Synthetic mod tree leaked into user data
- **Location:** `tests/DayLoopIntegrationTest.gd:20, 307-337, 421-437` (after fix)
- **Evidence:** `_create_synthetic_mods()` writes four folders under `user://integration_mods/`; before the fix only `.disabled` was removed.
- **Problem:** repeat runs left residue in the developer's `user://` directory.
- **Disposition: FIXED.** `_remove_dir_recursive()` deletes the whole tree in `_restore_environment()`. Verified: no `integration_mods` directory remains after a run.

### 8. [Low][Architecture] Harness header overstated "no private implementation calls"
- **Location:** `tests/DayLoopIntegrationTest.gd:4-7` (after fix)
- **Evidence:** the harness reads `pool_ui.get("_topics")` (`:174`) and `_game.get("_player_instance")` (`:441`, `:509`) — read-only probes because no public accessor exists.
- **Problem:** comment did not match the code.
- **Disposition: RULING (not fixed).** Corrected the header to say the assertions use observable behaviour plus a few read-only internal probes. Adding public accessors to `DialoguePoolUI`/`Game` purely for a test would touch production files for a verification ticket. Cost if wrong: a rename of those private fields breaks the harness with a null instead of a clear message; the failure is loud, not silent.

## Rulings

- **AC10 threshold is 50% documented functions, not 100%.** A per-function audit found 91 of ~300 shipped functions without a preceding `##` line, almost all trivial getters and `_ready()` stubs. Adding comments to all of them would touch ~20 production files for a verification ticket. The harness now prints the measured coverage (69%) so the threshold is visible; cost if wrong: a script with sparse-but-nonzero docs can still pass.

## Final verification

- `powershell -ExecutionPolicy Bypass -File tests\run_integration.ps1` → `ALL_018_CHECKS_PASSED`, `RESULT passed=41 failed=0`, `INTEGRATION_018_OK`.
- RED proof (before fix pass): forcing `DialogueFilter.build_pool()` to return `[]` failed 4 checks; reverted and re-verified green.
- Editor class-cache scan and `--quit-after 10` launch smoke: no new script errors; only pre-existing ticket-013 NavigationServer map-sync errors.
- No production source files were modified by this ticket; changes are confined to `tests/`, `doc/idea-v1-decisions.md`, and `doc/tickets/018-...md`.
