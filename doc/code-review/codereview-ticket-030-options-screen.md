# Code Review: ticket/030-options-screen vs master

- **Branch:** `ticket/030-options-screen`
- **Base:** `master` (merge-base: `5b856eb223620121b0b393db4f2823e77e81b725`)
- **Reviewed commit:** `8e2a5683061e86275522841f7dae127dd624e8d5`
- **Changed files:** 10
- **Findings:** 4 (Critical: 0, High: 0, Medium: 2, Low: 2)
- **Verification at review time:** `OPTIONS_030_OK` (19/19); all 12 other v1/v2 harnesses green.

## Findings

### 1. [Medium][Performance] Slider drag persists and rebuilds chunk config on every intermediate value

- **Location:** `scripts/Options.gd:109-114`, `scripts/Options.gd:119-155`; downstream `scripts/SettingsManager.gd:124,154-158,276-282,381-399`, `scripts/ChunkManager.gd:62-72`
- **Evidence:** The diff connects `value_changed` directly to the writers:
  ```gdscript
  + _volume_slider.value_changed.connect(_on_volume_changed)
  + _close_radius_spin.value_changed.connect(_on_close_radius_changed)
  ...
  + SettingsManager.set_master_volume(value / 100.0)
  ```
  `SettingsManager.set_master_volume()` calls `_write()` → `save()` → `_config.save(_config_path)` (`SettingsManager.gd:124`). `set_chunk_value()` (`SettingsManager.gd:276-282`) calls `_rebuild_chunk_config()` — a fresh `ChunkConfig` plus a 9-field re-derivation (`:381-399`) — then `_apply_chunk_config()` → `ChunkManager.set_config()`, which clears tick accumulators/promotions and loops every NPC (`ChunkManager.gd:62-72`). Godot's `Range.value_changed` fires continuously while dragging (the `Slider` signal list also exposes `drag_started`/`drag_ended`, confirmed by running `HSlider.get_signal_list()` headlessly). The decision record at `doc/idea-v2-decisions.md:181` states writes happen "on every committed control change", not every drag step.
- **Problem:** One volume drag can issue many synchronous `ConfigFile.save()` calls; one radius/rate adjustment can repeatedly reset NPC simulation state while the day is paused in the embedded pause-menu panel.
- **Recommendation:** Update the volume label on `value_changed` but persist/apply on the slider's `drag_ended(changed)` signal (or a short debounce timer), so feedback stays live without a disk write per frame. Keep discrete SpinBox commits on `value_changed`, and add a harness assertion that a multi-step simulated drag produces a single settings write.

### 2. [Medium][Bug] Near radius can be stored below close radius, so the UI disagrees with runtime

- **Location:** `scripts/Options.gd:58-59`, `scripts/Options.gd:126-131,146-149`; `scripts/ChunkManager.gd:211-212`
- **Evidence:** `_configure_int_spin(_close_radius_spin, 0, 32, ...)` and `_configure_int_spin(_near_radius_spin, 1, 64, ...)` set independent ranges, and `_write_chunk_int()` writes either field without an invariant. `ChunkManager._tier_for()` computes `var near_r: int = maxi(close_r, cfg.near_radius_chunks)` (`ChunkManager.gd:212`), so a stored pair such as `close = 32, near = 1` behaves as near = 32 while both the SpinBox and `SettingsManager.get_near_radius_chunks()` still report 1. `ChunkConfig.gd:20-21` documents the clamp. Harness T6/T7 only exercise compatible values (`close 4 / near 7`), so the path is untested.
- **Problem:** The Options screen can persist a contradictory radius pair and show a value the simulation never uses.
- **Recommendation:** At the UI boundary, raise `_near_radius_spin.min_value` whenever close changes and clamp/persist near up to at least close (and clamp the populated value on load); add a regression check that after raising close above near, both the SpinBox and `SettingsManager.get_near_radius_chunks()` report the effective value.

### 3. [Low][Architecture] Documented stable node paths omit the `*Row` container

- **Location:** `doc/idea-v2-decisions.md:184`; actual code `scripts/Options.gd:21-29`, `tests/OptionsTest.gd:61-74`
- **Evidence:** The decision record lists `SettingsScroll/SettingsBox/VolumeSlider`, `.../CloseRadiusSpin`, etc., but the shipped `@onready` paths are `$SettingsScroll/SettingsBox/VolumeRow/VolumeSlider`, `$SettingsScroll/SettingsBox/CloseRadiusRow/CloseRadiusSpin`, and the harness asserts those deeper paths. A harness written from the documented contract would fail `get_node_or_null()`.
- **Problem:** The written headless seam does not match the scene that ships.
- **Recommendation:** Update the decision record to the real paths including the `*Row` segment (cheapest fix; do not flatten a working layout).

### 4. [Low][SOLID] Back-action seam is duplicated in three screens

- **Location:** `scripts/Options.gd:17-18,179-189`; `scripts/PlaceholderScreen.gd:16,30-40`; `scripts/LoadGame.gd:22,210-219`
- **Evidence:** Options re-adds `var back_action: Callable = Callable()` and the same `set_back_action` / `_on_back_pressed` / `_default_back` bodies that already exist verbatim in PlaceholderScreen and LoadGame, while `doc/idea-v2-decisions.md:183` says the new screen "keeps PlaceholderScreen's `back_action` seam". `PauseMenu._embed_screen()` only checks `has_method("set_back_action")`, so divergent fallback behaviour would not be caught.
- **Problem:** Three copies of one callable/fallback contract must be kept in sync; the decision record overstates reuse.
- **Recommendation:** Extract a small shared `BackActionControl extends Control` base (or composition helper) and have all three screens use it, plus one harness check that all three fall back to `GameManager.show_main_menu()` for an invalid callable. Deferred as out-of-scope refactoring for ticket 030.

## Evidence audit

- Claim 1 — SUPPORTED: diff hunk plus `SettingsManager.gd`/`ChunkManager.gd` line references and a reproduced `HSlider.get_signal_list()` output.
- Claim 2 — SUPPORTED: `Options.gd` line references plus `ChunkManager.gd:212` and `ChunkConfig.gd:20-21`.
- Claim 3 — SUPPORTED: `doc/idea-v2-decisions.md:184` vs `Options.gd:21-29` and `OptionsTest.gd:61-74`.
- Claim 4 — SUPPORTED: matching member bodies at three cited locations plus `PauseMenu.gd:161-164`.
- **Verdict: PASS** — no unsupported or mixed claims.
