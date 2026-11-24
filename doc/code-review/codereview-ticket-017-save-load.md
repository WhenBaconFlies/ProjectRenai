# Code Review: Ticket 017 (Save/Load) — working tree vs master

- **Branch:** `master` (changes are uncommitted working-tree edits)
- **Base:** `master` (merge-base = current `HEAD`; review of `git diff` + untracked files)
- **Changed files:** 10 (`scripts/SaveGame.gd` new; `scripts/SaveManager.gd`, `scripts/GameManager.gd`, `scripts/Game.gd`, `scripts/Npc.gd`, `scripts/NpcSpawner.gd`, `scripts/TimeManager.gd`, `project.godot`, `doc/idea-v1-decisions.md`, `doc/tickets/017-save-load.md`)
- **Findings:** 6 (Critical: 0, High: 0, Medium: 1, Low: 5)
- **Reviewer:** code-review-expert (independent reviewer pass + evidence audit)

## Findings

### 1. [Medium][State fidelity] Malformed day snapshot restores saved NPCs before validation, producing a hybrid fresh day
- **Location:** `scripts/Game.gd:108-113`, `scripts/Game.gd:222-227`; `scripts/TimeManager.gd:358-360`; `scripts/SaveManager.gd:93-100`
- **Evidence:** `_ready()` spawns restored NPCs at line 110 (`_setup_npcs(loaded_save.npc_instances)`) before `_restore_from_save()` validates at line 224 (`if not TimeManager.restore_day_snapshot(save.day_snapshot): ... TimeManager.start_day(1)`). `restore_day_snapshot()` rejects only a missing `day`/`state` key (`TimeManager.gd:359-360`), while `load_slot()` checks only `is_compatible()` (version) at `SaveManager.gd:93`. Since older versions are intentionally accepted with no migration, a version-1 save with a differently shaped snapshot is reachable; on rejection the screen keeps last session's saved NPC stats/meters/positions while the player and day are fresh.
- **Problem:** The documented "recoverable error" path silently yields a hybrid day instead of a clean fallback.
- **Recommendation:** Validate the whole payload at the load gate (`SaveGame.is_well_formed()` called by `SaveManager.load_slot()`) and in `Game._ready()` **before** any NPC is spawned; move the day-snapshot restore ahead of NPC setup so a failed restore can rebuild fresh NPCs.

### 2. [Low][Contract] Older-version saves load silently instead of with the documented warning
- **Location:** `scripts/SaveManager.gd:93-100`; `scripts/SaveGame.gd:80-81`; `doc/idea-v1-decisions.md` (ticket-017 decisions)
- **Evidence:** A `version < CURRENT_VERSION` save passes `is_compatible()` (`SaveGame.gd:81`), so `load_slot()` goes from the rejection branch at line 93 directly to `_last_error = ""; return save` at lines 99-100. No warning is emitted anywhere. The decision record explicitly says older versions load *with a warning*.
- **Problem:** The forward-compatibility seam accepts old-format saves with no diagnostic, compounding finding 1.
- **Recommendation:** Add `if save.version < SaveGame.CURRENT_VERSION: push_warning(...)` after the compatibility check in `load_slot()`.

### 3. [Low][State bleed] `current_save` aliases live instances after restore; the deep-copy comment is false on the read path
- **Location:** `scripts/Game.gd:229-232`; `scripts/NpcSpawner.gd:127-133`; `scripts/SaveGame.gd:47-49`; `scripts/GameManager.gd:36-45`
- **Evidence:** `_player_instance = saved_player` (Game.gd:231) and `npc.setup(instance)` on elements of `save.npc_instances` (`NpcSpawner.gd:127-133`) bind the scene directly to the loaded SaveGame's resources. Dialogue resolution mutates meters/mood in place and `Npc._physics_process` writes `instance.position` each tick, so `GameManager.current_save` (set at `GameManager.gd:43`) diverges from the file immediately. `SaveGame.gd:47-49` claims later mutations cannot change a save still in memory.
- **Problem:** A future retry/restart path that reuses `current_save` would resurrect mutated state; the code comment promises an isolation guarantee it does not provide.
- **Recommendation:** Deep-copy instances at the restore boundary as well (`NpcInstance.from_snapshot(saved.snapshot())` for the player and every NPC passed to `spawn_from_instances()`), or correct the comment and clear `current_save` after a successful restore.

### 4. [Low][Robustness] Many-to-one slot sanitization and unenforced reserved names let distinct callers overwrite each other
- **Location:** `scripts/SaveManager.gd:207-223`, `:93`, `:56`; `doc/idea-v1-decisions.md` (ticket-017 decisions)
- **Evidence:** `_sanitize_slot()` replaces every disallowed character with `_` and truncates at 64 chars, so `"a/b"`, `"a b"`, `"a.b"` all resolve to `user://saves/a_b.tres`. `save_slot()` (line 56) accepts any name, including the reserved `autosave`/`manual` constants (line 93 region), so an arbitrary caller can overwrite the DayEnd checkpoint with no error (`save_slot` returns `true`).
- **Problem:** "Unlimited named slots" holds in count but not in identity; overwriting the autosave slot can destroy the DayEnd checkpoint.
- **Recommendation:** Append a short stable hash of the raw name when sanitization changes it (e.g. `raw.md5().substr(0, 8)`) and reject reserved names from general `save_slot()` callers, with an explicit internal bypass for autosave and the F5 handler.

### 5. [Low][Correctness] F9 recency tie-break picks the lexicographically smallest name within one millisecond
- **Location:** `scripts/SaveManager.gd:141-153`; `scripts/SaveGame.gd:59`
- **Evidence:** `saved_at` is millisecond resolution (`SaveGame.gd:59`). `get_last_saved_slot()` at line 149 breaks equal timestamps with `slot < best`, i.e. alphabetically, not by write order. Two saves in the same millisecond (e.g. scripted `autosave()` then `save_slot("manual")`) deterministically select `"autosave"` even when written first.
- **Problem:** F9 can load the wrong-of-two slots in a narrow but reproducible window.
- **Recommendation:** Persist a monotonic `write_seq` (max existing + 1 on each successful write) and compare it before `saved_at`; keep the name tie-break only as a final deterministic fallback.

### 6. [Low][Contract] Missing-template recovery warns only for the player; NPC template loss is silent
- **Location:** `scripts/Game.gd:229-232`, `scripts/Game.gd:253-269`; `scripts/NpcSpawner.gd:110-140`; `scripts/NpcInstance.gd:136-146`
- **Evidence:** `_resolve_saved_template()` is called only for the saved player (`Game.gd:232`). `spawn_from_instances()` does no template lookup (`NpcSpawner.gd:110-140`), and lazy `NpcInstance.resolve_template()` returns null without logging (`NpcInstance.gd:136-146`). The decision record states a missing template logs a warning and degrades the instance.
- **Problem:** An NPC that lost its authored template loads without a crash (correct) but gives the operator no diagnostic identifying which NPC lost AI/dialogue gating.
- **Recommendation:** Emit one consolidated warning during restore listing every instance id (player and NPCs) whose template is missing or has an empty id.

## Evidence Audit

### Claims
1. [SUPPORTED] Finding 1 — verified `Game.gd:108-113`, `Game.gd:222-227`, `TimeManager.gd:358-360`, `SaveManager.gd:93-100` by direct read; the spawn-before-validate ordering is literal.
2. [SUPPORTED] Finding 2 — verified `SaveManager.gd:93-100` and `SaveGame.gd:80-81`; no warning branch exists.
3. [SUPPORTED] Finding 3 — verified `Game.gd:229-232`, `NpcSpawner.gd:127-133`, `SaveGame.gd:47-49`; the in-memory alias is direct.
4. [SUPPORTED] Finding 4 — verified `SaveManager.gd:207-223` sanitization body and the absence of a reserved-name guard in `save_slot()`.
5. [SUPPORTED] Finding 5 — verified `SaveManager.gd:141-153` tie-break expression and `SaveGame.gd:59` timestamp resolution.
6. [SUPPORTED] Finding 6 — verified the single call site of `_resolve_saved_template()` in `Game.gd` and the no-log null return in `NpcInstance.gd:136-146`.

### Verdict: PASS
- Unsupported claims: 0
- Action required: none for the review record; all six findings were accepted for implementation.

## Verified non-issues (not defects)
- Autosave timing: `state_changed` fires before `_request_autosave()`; DayEnd follows PERIOD4 where AI is already disabled, so empty saved goals are faithful.
- Restore into non-free-time states: `restore_day_snapshot()` sets state/elapsed/records consistently and `sync_ai_state(true)` disables AI correctly.
- Version rejection: `GameManager.load_slot()` leaves `current_save` untouched when `load_slot()` returns null.
- Player position restore ordering: `Player._ready()` queues its spawn snap before `Game._ready()` queues the saved-position apply; deferred FIFO makes the saved position win.
- AI resume: `resume_saved_goal()` consumes `goal_destination`; `set_ai_enabled(..., preserve_goal=true)` does not re-roll a saved `class:` goal.
- Duplicate provider / mid-play load: the provider Callable is overwritten, not accumulated; `change_scene_to_file` is deferred and safe from `_unhandled_input`.
- F5/F9 keycodes in `project.godot:69,74` are the correct `KEY_F5`/`KEY_F9` values (verified against Godot's `Key` enum: 4194336 / 4194340).
