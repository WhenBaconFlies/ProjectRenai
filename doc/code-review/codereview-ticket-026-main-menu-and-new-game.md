# Code Review: Ticket 026 (Main Menu + New Game routing)

- **Branch:** `ticket/026-main-menu-and-new-game` (HEAD `b3ae326`)
- **Base:** `master` (merge-base: `240e37fbda32755705901dfcb8ea9fceafc944ab`); ticket-scoped diff base: `1ddab4243e136204828058502ee66dd553e49bbe`
- **Changed files:** 15 (scoped to ticket 026)
- **Findings:** 4 (Critical: 0, High: 0, Medium: 2, Low: 2)
- **Verification baseline:** `tests/run_main_menu_tests.ps1` → `ALL_026_CHECKS_PASSED` (22/22); regressions 018, 019, 020, 021, 022, 023, 024, 025 all report `*_OK`; default `--headless --quit` launch loads `MainMenu.tscn` with no parse errors.

## Findings

### 1. [Medium][Test gap] The real Quit exit path is never exercised
- **Location:** `scripts/MainMenu.gd:52-58`, `scripts/GameManager.gd:63-65`, `tests/MainMenuTest.gd:66-70,158`
- **Evidence:** The shipped path is `_on_quit_pressed()` → `_default_quit()` → `GameManager.quit_game()` → `get_tree().quit()`. The harness injects `Callable(self, "_record_quit")` and asserts only `_quit_calls == 1`; `_record_quit()` (`tests/MainMenuTest.gd:22-23`) increments a counter. Neither `_default_quit()` nor `quit_game()` is invoked in the harness, which terminates via its own `get_tree().quit()` at `:158`.
- **Problem:** Acceptance criterion "Quit exits cleanly" is inferred from a fake callable rather than observed on the production path.
- **Recommendation:** Add a separate headless invocation that boots `MainMenu`, emits the real `QuitButton.pressed`, and asserts a clean process exit (marker printed before `get_tree().quit()` plus exit code 0), or give `GameManager.quit_game()` an injectable callable seam mirroring `MainMenu.set_quit_action()`.

### 2. [Medium][Test gap] Three of the five button-to-route connections are never pressed
- **Location:** `scripts/MainMenu.gd:22-26`, `tests/MainMenuTest.gd:46-59,102-116`
- **Evidence:** `_ready()` connects five `pressed` signals. The harness checks node names/text for all five but emits only Quit (`:69`) and New Game (`:75`). The Load Game / Options / Mods Menu routes are invoked directly with `GameManager.call(str(route[0]))` (`:102-103`), bypassing `LoadGameButton`, `OptionsButton`, and `ModsButton`.
- **Problem:** A missing or mis-wired `pressed.connect()` for those three buttons would still pass all 22 checks.
- **Recommendation:** In the routes loop, fetch each corresponding button from the live `MainMenu` and emit `button.pressed` instead of calling `GameManager.call()`; keep the resulting scene-name assertions unchanged.

### 3. [Low][Test gap] A stale log can produce a false pass when Godot emits nothing
- **Location:** `tests/run_main_menu_tests.ps1:27,35,39,42`
- **Evidence:** The runner uses a fixed `$logPath`, pipes Godot through `Tee-Object -FilePath $logPath`, then decides pass solely from that file. Verified in review: writing `ALL_026_CHECKS_PASSED` to the path and piping an empty array through `Tee-Object` left the marker intact — `Tee-Object` does not truncate when the pipeline emits nothing.
- **Problem:** A crashed or non-starting Godot run could be reported as `MAIN_MENU_026_OK` from a previous run's log.
- **Recommendation:** `Remove-Item $logPath -ErrorAction SilentlyContinue` immediately before launching Godot (or capture output directly with `$output = (& $GodotPath ... 2>&1 | Out-String)` and drop the log file).

### 4. [Low][Test gap] Repeated button presses have no in-flight guard or test
- **Location:** `scripts/GameManager.gd:97-105`, `scripts/MainMenu.gd:35-49`, `tests/MainMenuTest.gd:69,75,102-114`
- **Evidence:** `change_scene()` sets `current_scene_path` and always calls `call_deferred("_do_change_scene", path)`; `_do_change_scene()` unconditionally calls `change_scene_to_file()`. Every menu handler routes with no debounce, and the harness presses each button once.
- **Problem:** A double-click in one frame queues two deferred scene swaps; there is no guard and no test that a single press causes exactly one transition.
- **Recommendation:** Add a pending-swap guard to `GameManager.change_scene()` (ignore repeat calls until `_do_change_scene()` completes) and add a harness check that emits the same button twice in one frame, asserting one transition and no `[GameManager]` error.

## Evidence Audit

- Claim 1: SUPPORTED — `scripts/MainMenu.gd:52-58`, `scripts/GameManager.gd:63-65`, `tests/MainMenuTest.gd:66-70,158`.
- Claim 2: SUPPORTED — `scripts/MainMenu.gd:22-26`, `tests/MainMenuTest.gd:46-59,102-103`.
- Claim 3: SUPPORTED — `tests/run_main_menu_tests.ps1:27,35,39,42` plus the reviewer's `Tee-Object` command result.
- Claim 4: SUPPORTED — `scripts/GameManager.gd:97-105`, `scripts/MainMenu.gd:35-49`, `tests/MainMenuTest.gd:69,75,102-114`.
- **Verdict: PASS** — 0 unsupported or mixed claims.
