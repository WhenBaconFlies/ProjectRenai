# Code Review: Ticket 025 (SettingsManager + ConfigFile persistence)

- **Branch:** `ticket/024-conversation-overlay-and-game-wiring` (changes are uncommitted in the working tree)
- **Base:** `master` (merge-base: `240e37fbda32755705901dfcb8ea9fceafc944ab`)
- **Changed files:** 8
  - tracked: `doc/idea-v2-decisions.md`, `project.godot`, `scripts/AudioManager.gd`
  - new: `scripts/SettingsManager.gd`, `tests/SettingsManagerBootstrap.gd`, `tests/SettingsManagerBootstrap.tscn`, `tests/SettingsManagerTest.gd`, `tests/run_settings_manager_tests.ps1`
- **Findings:** 5 (Critical: 0, High: 0, Medium: 2, Low: 3)
- **Verification baseline:** `tests/run_settings_manager_tests.ps1` → `ALL_025_CHECKS_PASSED` (17/17); regressions 018/019/020/021/022/023/024 all report `*_OK`.

## Findings

### 1. [Medium][Bug] Setters report success when the ConfigFile write fails
- **Location:** `scripts/SettingsManager.gd:463-466` (also `:153-156`, `:212-216`, `:231-233`, `:330-335`)
- **Evidence:** `save()` returns `false` and records `_last_error` at `scripts/SettingsManager.gd:123-130`, but `_write()` at `:463-466` calls `save()` and discards the result, then unconditionally emits `settings_changed`. All public setters are `void`, so a caller (ticket 030's Options screen) has no way to learn that `user://settings.cfg` was not written; memory, runtime targets, and disk diverge silently.
- **Problem:** Persistence failure in a read-only or full `user://` location looks like a successful settings change.
- **Recommendation:** Have `_write()` return `bool` from `save()` and propagate it from the setters (or emit a `save_failed` signal alongside `settings_changed`) so the Options screen can surface the failure; keep applying the in-memory/runtime value only if that is the intended degradation.

### 2. [Medium][Test gap] Startup re-application is not asserted after `reload()`
- **Location:** `tests/SettingsManagerTest.gd:97-104` (compare `:55-61`)
- **Evidence:** T5/T6 (`:55-61`) assert immediate application only on *write*. The round-trip section calls `SettingsManager.reload()` at `:97` and then checks only `SettingsManager` getters (`:100-104`). Ticket 025's own acceptance line reads "Reads apply on startup to `AudioManager`, the display, and `ChunkManager.config`". Removing `apply_all()` from `reload()` (`scripts/SettingsManager.gd:119`) would leave all 17 checks green.
- **Problem:** A regression in the startup-application path — the ticket's core behavior — is undetectable by the harness.
- **Recommendation:** After `reload()` at `:97`, assert `is_equal_approx(AudioManager.get_master_volume(), 0.62)` and `_dicts_equal(ChunkManager.get_config().to_dictionary(), expected_chunk)`. Display application remains headless-skipped by design, so assert `is_restart_required("display")` there instead.

### 3. [Low][Bug] `clear_mod_flag()` cannot remove a wrong-typed mod key
- **Location:** `scripts/SettingsManager.gd:344-351` (with `:362-368`)
- **Evidence:** `_load_values()` copies only `bool`-typed values from the `mods` section into `_mods` (`:367-368`). `clear_mod_flag()` early-returns when `_mods` lacks the id (`:345-346`), so a key authored as a string/int in `settings.cfg` survives on disk even after a clear request. T13 in `tests/SettingsManagerTest.gd` exercises only a bool-valued flag.
- **Problem:** A malformed mod flag becomes permanently unclearable through the public API.
- **Recommendation:** Remove the `_mods.has(mod_id)` early return; erase `SECTION_MODS`/`mod_id` from `_config` whenever the key exists, then save and emit. Keep the `_mods.erase()` as a no-op-safe cleanup.

### 4. [Low][Architecture] Default master volume has two sources of truth
- **Location:** `scripts/AudioManager.gd:12` and `scripts/SettingsManager.gd:41`
- **Evidence:** `_master_volume: float = 0.8` in AudioManager duplicates `DEFAULT_MASTER_VOLUME: float = 0.8` in SettingsManager. `AudioManager._ready()` (`:15-16`) applies its own value before `SettingsManager._ready()` calls `reload()` → `apply_all()` → `_apply_volume()` (`scripts/SettingsManager.gd:109-119`, `:474-476`). A one-sided edit makes the pre-reload volume differ from the settings default.
- **Problem:** The startup volume depends on which constant was edited last.
- **Recommendation:** Define the default once — e.g. `SettingsManager`'s fallback default reads `AudioManager.get_master_volume()` at load time, or AudioManager keeps a neutral default and relies on the autoload ordering for the real value.

### 5. [Low][Testing] Expected corrupt-config parse error renders as a PowerShell error record
- **Location:** `tests/run_settings_manager_tests.ps1:35`
- **Evidence:** The passing run's output contains `Godot_v4.2.1... : ERROR: ConfigFile parse error ... Unexpected EOF while parsing simple tag.` followed by a `NativeCommandError` block, then `SETTINGS_MANAGER_025_OK`. The error comes from the deliberately malformed T15 fixture (`tests/SettingsManagerTest.gd:163-169`) and is expected.
- **Problem:** A green run prints a red-looking error block, obscuring real failures in CI logs.
- **Recommendation:** Route only stdout through `Tee-Object` and append stderr to the log (`2>> $logPath`) so the expected Godot diagnostic is captured but not rendered as a PowerShell error record.

## Evidence audit

1. [SUPPORTED] Finding 1 — `scripts/SettingsManager.gd:123-130` (save returns bool), `:463-466` (result discarded).
2. [SUPPORTED] Finding 2 — `tests/SettingsManagerTest.gd:55-61,97-104`; `scripts/SettingsManager.gd:109-119`.
3. [SUPPORTED] Finding 3 — `scripts/SettingsManager.gd:344-346,362-368`.
4. [SUPPORTED] Finding 4 — `scripts/AudioManager.gd:12,15-16`; `scripts/SettingsManager.gd:41`.
5. [SUPPORTED] Finding 5 — `tests/run_settings_manager_tests.ps1:35`; observed runner output.

**Verdict:** PASS — all five claims carry file:line evidence and a concrete fix. No vague or praise-only claims were kept.
