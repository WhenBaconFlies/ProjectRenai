# Code Review: Ticket 027 (Load Game named-slot UI)

- **Branch:** `master` (work is uncommitted; HEAD `000c21043fbc74c98accbee66d5d5de91765bddb`)
- **Base:** `master` (merge-base: `000c21043fbc74c98accbee66d5d5de91765bddb`; ticket-scoped diff against HEAD)
- **Changed files:** 7 — `doc/idea-v2-decisions.md`, `scenes/LoadGame.tscn`, `scripts/LoadGame.gd`, `tests/LoadGameBootstrap.gd`, `tests/LoadGameBootstrap.tscn`, `tests/LoadGameTest.gd`, `tests/run_load_game_tests.ps1`
- **Findings:** 3 (Critical: 0, High: 0, Medium: 1, Low: 2)
- **Verification baseline:** `tests/run_load_game_tests.ps1` → `ALL_027_CHECKS_PASSED` (27/27, `LOAD_GAME_027_OK`); regressions 018 (42/42), 019, 020, 021 (23/23), 022 (23/23), 023 (35/35), 024 (42/42), 025 (21/21), 026 (23/23) all report `*_OK`.

## Findings

### 1. [Medium][Bug] Long sanitized slot names are listed but cannot be loaded or deleted

- **Location:** `scripts/LoadGame.gd:40`, `:108`, `:143`, `:152`; root cause `scripts/SaveManager.gd:257-261`
- **Evidence:** The UI feeds each name from `list_slots()` straight back into `load_slot()` / `delete_slot()`:
  ```gdscript
  # scripts/LoadGame.gd:40,108,143,152
  var slots: Array[String] = SaveManager.list_slots()
  var save: SaveGame = SaveManager.load_slot(slot)
  if not GameManager.load_slot(slot):
  if SaveManager.delete_slot(slot):
  ```
  `SaveManager._sanitize_slot()` is not idempotent for a raw name longer than 55 characters containing an invalid character at or after position 55 (`scripts/SaveManager.gd:257-261`):
  ```gdscript
  if cleaned.length() > 55:
      cleaned = cleaned.substr(0, 55)
  if was_changed:
      cleaned = cleaned + "_" + ("%08x" % (absi(raw.hash()) % 0x100000000))
  ```
  A name written under the first, hashed 64-character form is re-sanitized from its own on-disk name into a 55-character form on the next lookup. Independent Godot 4.2.1 probe using the project's own `SaveManager`: `RAW_LEN=61 FIRST_LEN=64 SECOND_LEN=55`, `IDEMPOTENT=false`, `STORED_PATH=user://saves/…_b5d44a61.tres`, `RELOAD_PATH_MATCHES=false`. The listed row shows "unreadable save", Load fails, and Delete fails with "save slot does not exist".
- **Problem:** Ticket ACs "selecting a slot loads it" and "a slot can be deleted" fail for a valid class of named slots, and the recorded decision that "a corrupt slot can always be removed by the player" (`doc/idea-v2-decisions.md:143`) is violated.
- **Recommendation:** Make `_sanitize_slot()` idempotent: when a suffix will be appended, truncate `cleaned` to `55 - 9` characters *before* appending `_<8 hex>` so every stored name is at most 55 characters and a second pass leaves it unchanged. Add a round-trip assertion (`get_save_path(list_slots()[i]) == get_save_path(raw)`) to the headless harness so the contract is locked down.

### 2. [Low][Test gap] Recorded decision behaviors are not exercised by the harness

- **Location:** `tests/LoadGameTest.gd:106-125`, `:140-144`; `doc/idea-v2-decisions.md:143`; `scripts/LoadGame.gd:110`, `:143-144`, `:147-148`
- **Evidence:** The harness seeds only two well-formed slots (`tests/LoadGameTest.gd:48-51`) and arms/cancels/deletes the same row (`tests/LoadGameTest.gd:109-125`). No check writes a truncated `.tres` to trigger the `"unreadable save (%s)"` branch at `scripts/LoadGame.gd:110` and then delete that row, despite the decision at `doc/idea-v2-decisions.md:143`. No check arms one row and presses a different row's Delete, despite the code comment at `scripts/LoadGame.gd:147-148` ("Pressing a different row's Delete moves the pending state instead of deleting two slots"). The failed-load status branch (`scripts/LoadGame.gd:143-144`) is never triggered.
- **Problem:** Three behaviors promised by the implementation and decision record can regress unnoticed.
- **Recommendation:** Add checks that (a) seed a corrupt slot file, assert a row appears whose `MetaLabel` contains `"unreadable"` and that its Delete removes the file; (b) arm Delete on `SLOT_A`, press Delete on `SLOT_B`, assert `SLOT_A` still exists with text `"Delete"` and `SLOT_B` shows `"Confirm Delete?"`; (c) press Load on the corrupt slot and assert the `StatusLabel` contains SaveManager's error message. Update `EXPECTED_CHECKS` accordingly.

### 3. [Low][Performance] `refresh()` deserializes every save file synchronously

- **Location:** `scripts/LoadGame.gd:37-46`, `:107-110`; `scripts/SaveManager.gd:93`, `:114-129`
- **Evidence:** Each `refresh()` (called on `_ready()` at `:32` and after delete/cancel at `:156`/`:174`) calls `SaveManager.list_slots()` and then `_metadata_text(slot)` per row; `_metadata_text` calls `SaveManager.load_slot(slot)` → `ResourceLoader.load(path)` (`scripts/SaveManager.gd:93`), a full `.tres` deserialization to read five metadata fields. `SaveManager.gd:19-20` states there is no slot cap ("unlimited slots"), so cost is O(N) full resource loads per refresh with no bound.
- **Problem:** With many slots, entering the screen or deleting one re-reads every save synchronously on the UI thread.
- **Recommendation:** Read metadata without a full resource load — e.g. a small per-slot metadata sidecar written by `SaveManager.save_slot()`, or at minimum cache the last `_rows` metadata and update only the affected row after a delete instead of calling `refresh()` for the whole list.

## Evidence Audit

- Claim 1: SUPPORTED — `scripts/LoadGame.gd:40,108,143,152`, `scripts/SaveManager.gd:257-261`, plus the independent Godot 4.2.1 probe output quoted above (`IDEMPOTENT=false`, `RELOAD_PATH_MATCHES=false`).
- Claim 2: SUPPORTED — `tests/LoadGameTest.gd:48-51,106-125,140-144`, `doc/idea-v2-decisions.md:143`, `scripts/LoadGame.gd:110,143-144,147-148`.
- Claim 3: SUPPORTED — `scripts/LoadGame.gd:32,37-46,107-110,156,174`, `scripts/SaveManager.gd:19-20,93,114-129`.
- **Verdict: PASS** — 0 unsupported or mixed claims.
