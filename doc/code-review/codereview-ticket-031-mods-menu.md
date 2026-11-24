# Code Review: ticket/031-mods-menu vs master

- **Branch:** `ticket/031-mods-menu`
- **Base:** `master` (merge-base: `e6dbbb7ea9412c0b78bd9d343ce29d6fd44d69dd`)
- **Reviewed commit:** `bd78c08815a02246693076b5daabd511a0925b86` (line numbers below refer to this commit)
- **Changed files:** 9
- **Findings:** 6 (Critical: 0, High: 1, Medium: 2, Low: 3)
- **Verification at review time:** `MODS_MENU_031_OK` (24/24) plus all 13 regression harnesses green.

## Findings

### 1. [High][Bug] Toggling a mod does not persist visually when the menu is reopened in the same session

- **Location:** `scripts/ModsMenu.gd:42,94,116,119`; `scripts/ModLoader.gd:201-202,667`; `scripts/PauseMenu.gd:150-158`; `scripts/GameManager.gd:105-119`
- **Evidence:** Rows take toggle state from the load-time snapshot, not the settings source of truth:
  ```gdscript
  _mods = ModLoader.get_installed_mods()                       # ModsMenu.gd:42
  toggle.button_pressed = bool(entry.get("settings_enabled", true))  # ModsMenu.gd:94
  ```
  `get_installed_mods()` returns `_installed_mods.duplicate(true)` (`ModLoader.gd:201-202`) and `settings_enabled` is captured once at load (`ModLoader.gd:667`). `_on_toggle` mutates only its own deep copy (`ModsMenu.gd:116`). Both entry paths create a fresh instance — `PauseMenu._embed_screen()` instantiates on every Mods click (`PauseMenu.gd:150-158`) and the Main Menu route uses `GameManager.change_scene()` (`GameManager.gd:105-119`). Reopening therefore shows a checked toggle and a hidden `RestartNotice` even though `user://settings.cfg` holds `false`. Harness T11–T14 stay inside one instance, so this is untested.
- **Problem:** A player who disables a mod, backs out and reopens the menu sees the toggle appear to revert and loses the pending-restart reminder.
- **Recommendation:** Initialise each toggle from the live setting (`SettingsManager.get_mod_enabled(mod_id)`) rather than the frozen snapshot flag, and derive the restart notice on entry by comparing live settings against the snapshot's `settings_enabled`.

### 2. [Medium][Bug] Duplicate-id discovery skips reuse the surviving mod's id

- **Location:** `scripts/ModLoader.gd:399,633-655,668-682`; `doc/idea-v2-decisions.md:193`
- **Evidence:** The duplicate branch passes the mod id while both other discovery-skip branches pass the folder name:
  ```gdscript
  _note_discovery_skip(mod_id, folder, "duplicate mod id", root_index, manifest)  # :399
  _note_discovery_skip(entry, folder, "missing %s" % MANIFEST_FILE, ...)         # :379
  ```
  The surviving mod also gets an entry with the same id at `ModLoader.gd:668-682`, so `get_installed_mods()` contains two entries with identical `id` — one `loaded`, one `skipped` — and the UI prints two identical `[id]` labels (`ModsMenu.gd:64`). The decision record states discovery skips use "the folder name as `id`". No duplicate-id fixture exists in the harness.
- **Problem:** Consumers that key rows by id (as `ModsMenuTest.gd:248-253,264-268` does) silently pick the wrong entry; the written contract disagrees with the code.
- **Recommendation:** Pass the folder name as `id` for the duplicate-id skip, with blank metadata like the other discovery skips; add a harness assertion that the skip is listed under its folder name with the `duplicate mod id` reason.

### 3. [Medium][UI] Author-hard-disabled mods render a checked but disabled "Enabled" toggle

- **Location:** `scripts/ModLoader.gd:666-677`; `scripts/ModsMenu.gd:88,94-95`
- **Evidence:** For `manifest.enabled == false`, `_build_installed_mods` sets `author_enabled=false`, `enabled=false`, `togglable=false` but leaves `settings_enabled` at its default `true`. The row then shows `"Skipped — disabled (manifest enabled=false)"` (`ModsMenu.gd:88`) directly above a greyed-out CheckButton whose `button_pressed` is `true` (`ModsMenu.gd:94-95`). The harness never writes `enabled` in its fixtures.
- **Problem:** The control contradicts its own status line and the ticket's "disabled mods show as disabled" requirement.
- **Recommendation:** Initialise the toggle from the effective/enabled state (and gate it on `togglable`) so locked rows read as off.

### 4. [Low][UI] Fixed-width notice and unwrapped metadata at supported 320 px resolutions

- **Location:** `scripts/SettingsManager.gd:45`; `scenes/ModsMenu.tscn:41,47-61`; `scripts/ModsMenu.gd:67-81`
- **Evidence:** `MIN_RESOLUTION_DIMENSION = 320` permits a 320 px window. `RestartNotice` uses `anchor_left/right = 0.5` with `offset_left/right = ±380` (`ModsMenu.tscn:50,54,56`), a fixed 760 px label that is clipped at that width. `MetaLabel` composes version + author + all dependencies + root on one unwrapped line (`ModsMenu.gd:76-81`, default `autowrap_mode = 0`) while `ModScroll` disables horizontal scrolling (`ModsMenu.tscn:41`).
- **Problem:** The notice text and long dependency lists become unreadable on small supported windows.
- **Recommendation:** Use full-width anchors for the notice and enable word-smart autowrap on `MetaLabel`/`StatusLabel` (or allow horizontal scrolling in the host).

### 5. [Low][Bug] Ignored save results make a failed toggle look successful

- **Location:** `scripts/SettingsManager.gd:346-351,361-369`; `scripts/ModsMenu.gd:112-119`
- **Evidence:** `set_mod_enabled()` and `clear_mod_flag()` return `false` when `ConfigFile.save()` fails, but `_on_toggle` discards both return values and still sets `entry["settings_enabled"]` and reveals the notice:
  ```gdscript
  if pressed:
      SettingsManager.clear_mod_flag(mod_id)
  else:
      SettingsManager.set_mod_enabled(mod_id, false)
  ```
- **Problem:** On a write error the toggle flips and promises a restart, but next launch restores the old flag.
- **Recommendation:** Capture the return value; on failure revert the button, keep the notice hidden and surface `SettingsManager.get_last_error()`.

### 6. [Low][Architecture] Restart notice text has two sources of truth

- **Location:** `scripts/ModsMenu.gd:20`; `scenes/ModsMenu.tscn:59`
- **Evidence:** `const RESTART_TEXT = "Restart required: mod changes take effect on next launch."` duplicates the scene's `text = "Restart required: mod changes take effect on next launch."`; the scene value is shown until the first toggle, after which the constant is written into the same label.
- **Problem:** Editing one copy leaves the other stale.
- **Recommendation:** Set the label text from the constant in `_ready()` and remove the scene-level literal.

## Evidence audit

- Claim 1 — SUPPORTED: diff hunk plus `ModLoader.gd:201-202,667`, `PauseMenu.gd:150-158` and `GameManager.gd:105-119` line references; harness T11–T14 confined to one instance.
- Claim 2 — SUPPORTED: exact added line at `ModLoader.gd:399` vs the sibling branches at `:379,388`, the second snapshot entry at `:668-682`, and the decision text at `doc/idea-v2-decisions.md:193`.
- Claim 3 — SUPPORTED: `ModLoader.gd:666-677` fields vs `ModsMenu.gd:88,94-95` UI construction; fixture writer never sets `enabled`.
- Claim 4 — SUPPORTED: `SettingsManager.gd:45`, `ModsMenu.tscn:41,50,54,56,59` and `ModsMenu.gd:76-81`.
- Claim 5 — SUPPORTED: `SettingsManager.gd:346-351,361-369` return values vs `ModsMenu.gd:112-119`.
- Claim 6 — SUPPORTED: identical literal at `ModsMenu.gd:20` and `ModsMenu.tscn:59`.
- **Verdict: PASS** — no unsupported or mixed claims.

## Resolutions after review

- **Finding 1 — fixed:** toggles now initialise from `SettingsManager.get_mod_enabled()`; `_has_pending_restart()` compares live flags to the load-time snapshot on entry and shows the notice accordingly. New harness check `T14b` failed before the fix and passes after.
- **Finding 2 — fixed:** duplicate-id skips now record the folder name with blank metadata. New harness check `T3b` failed before and passes after.
- **Finding 3 — fixed:** toggle state is gated on `togglable` and reads the live flag, so author-disabled and invalid rows show off. New harness check `T10b` failed before and passes after.
- **Finding 6 — fixed with finding 1:** `_ready()` now sets the notice text from `RESTART_TEXT`; the scene literal was removed.
- **Finding 4 — deferred (Low):** layout polish at 320 px; no gameplay or persistence effect, and the affected labels are readable at the project's normal 1280×720 default.
- **Finding 5 — deferred (Low):** `ConfigFile.save()` failure is an environment error path; the flag still lives in memory for the session and no data is lost, so it does not affect the ticket's acceptance criteria.
- **Post-fix verification:** `MODS_MENU_031_OK` (27/27) and all 14 harnesses (018–031) green.
