# Code Review: Ticket 011 (working tree) vs master

- **Branch:** master (ticket 011 work is uncommitted in the working tree)
- **Base:** master (working-tree diff against HEAD `d1d6804`)
- **Changed files:** 5 (4 modified + 1 new design doc)
- **Findings:** 10 (Critical: 0, High: 2, Medium: 4, Low: 4)

Reviewers: `code-reviewer`, `general` (independent passes), plus direct headless
reproductions on the real checkout (Godot 4.2.1). Duplicate findings were merged.
Every finding below has a `file:line`, concrete evidence, and a concrete fix.

## Findings

### 1. [High][Bug] Day starts before the Game scene exists; the initial signals are lost to scene listeners
- **Location:** `scripts/GameManager.gd:27-29`, `scripts/GameManager.gd:46-49`
- **Evidence:** The comment at 27-28 promises "listeners wired in the Game scene's `_ready()` see the day_started / state_changed signals". `change_scene_to_file()` defers the actual swap until after the deferred-call queue flushes, so `call_deferred("_start_new_day")` runs first. Direct headless probe on this checkout:
  ```
  EVENT_ORDER=day_started, game_scene_ready
  ```
  Independent reviewer probe: `ORDER day_started:1 current_scene=<null> game_scene_ready=false`.
- **Problem:** `day_started` and the first `state_changed` are emitted while `current_scene` is still null, so any listener connected in a Game-scene `_ready()` (tickets 013/018) silently misses day 1.
- **Recommendation:** Start the day from the new scene's `_ready()` (a small root script on `Game.tscn` calling `TimeManager.start_day(1)`), or make `_do_change_scene()` await the scene swap before calling `_start_new_day()`. Remove or correct the misleading comment.

### 2. [High][Bug] `advance()` discards all leftover time at a phase boundary; the multi-boundary loop is dead code
- **Location:** `scripts/TimeManager.gd:170-179`, `scripts/TimeManager.gd:363-364`
- **Evidence:** Line 173 subtracts `duration` from `_phase_elapsed`, then line 174 calls `_complete_and_advance()` → `_enter_state()`, which resets `_phase_elapsed = 0.0` at line 364, wiping the remainder. Direct probe on this checkout:
  ```
  advance(1000.0) -> state=FREETIME1 elapsed=0 day=1
  advance(1000.0) -> state=PERIOD2   elapsed=0 day=1
  ```
  (~955 s and then ~990 s discarded.) This contradicts the public doc at lines 148-149: "tests call it with large deltas to cross phase boundaries deterministically".
- **Problem:** The documented large-delta seam advances only one phase per call and loses elapsed time, so a test or catch-up tick cannot cross multiple boundaries.
- **Recommendation:** Preserve the carry locally and restore it after the transition:
  ```gd
  var carry := _phase_elapsed - duration
  _complete_and_advance()
  if _running:
      _phase_elapsed += carry
  ```
  then recompute `duration` and keep the `guard`. Do not rely on `_phase_elapsed` surviving `_enter_state()`.

### 3. [Medium][Bug] `day_started` is emitted in a different state on rollover than on fresh start
- **Location:** `scripts/TimeManager.gd:137-138`, `scripts/TimeManager.gd:372-375`
- **Evidence:** `start_day()` emits after `_enter_state(PERIOD1)` (state = PERIOD1), but the `NEXTDAY` branch of `_enter_state()` emits while state = NEXTDAY. Reviewer probe:
  ```
  day_started day=1 state_at_emit=PERIOD1 period=1
  day_started day=2 state_at_emit=NEXTDAY period=0
  ```
- **Problem:** A `day_started` subscriber calling `get_state()`/`get_current_period()` gets contradictory answers depending on which day it is.
- **Recommendation:** Emit from one place — set a pending flag in `start_day()` and in the `NEXTDAY` branch, then emit on entry to `PERIOD1` in `_enter_state()` and clear the flag. Remove the direct emits at lines 138 and 375.

### 4. [Medium][Bug] Entering BREAK mid-class drops that period's record and restarts the day at Period1
- **Location:** `scripts/TimeManager.gd:237-247`, `scripts/TimeManager.gd:347-356`
- **Evidence:** `start_break_day()` calls `_enter_state(BREAK)` directly, bypassing the `_record_period()` that `_complete_and_advance()` performs; `end_break_day()` unconditionally enters `PERIOD1`. Reviewer probe (advance 10 s into PERIOD1, break, end break):
  ```
  PROBE5 state=PERIOD1 attendance_keys=[]
  ```
- **Problem:** A break entered from `FREETIME2` or mid-`PERIOD3` replays earlier periods and loses partial attendance/grade data; the docs only justify "BREAK is separate, not exercised in v1", not a reset.
- **Recommendation:** Save `_state_before_break` / `_phase_elapsed_before_break` on entry, record the interrupted period if leaving a `PERIODx`, and restore on exit. Alternatively restrict `start_break_day()` to a day boundary and document that contract.

### 5. [Medium][Bug] Exported player id is ignored and the default player grade uses zero INT/WIS
- **Location:** `scripts/TimeManager.gd:81-83`, `:103`, `:208`, `:437-446`, `:451-459`
- **Evidence:** `@export var player_character_id = "player"` is never read; `_player_id` is hard-coded at declaration and `_ensure_roster()` appends `_player_id`. Reviewer probe after `tm.player_character_id = "custom_player"`:
  ```
  PROBE2 roster=["player", "char:mod_sample"]  (expected custom_player present)
  ```
  With `player_template_id == ""`, `_stats_for("player")` falls through both registry lookups to `{"intelligence": 0, "wisdom": 0}`, so the player always gets `score=60, letter="C", bonus=1` while NPCs use real template INT/WIS.
- **Problem:** Inspector configuration has no effect on the default path, and acceptance checkbox 5 ("bonus from attendance + INT/WIS") is only truly satisfied for NPCs.
- **Recommendation:** Initialize `_player_id` from `player_character_id` in `_ready()` (keep `set_roster()` as the explicit override) and define the v1 player-stat source — either default `player_template_id` to an authored template that is actually in a registry, or have `GameManager`/ticket 012 inject stats via `set_stats_provider()`. Record the choice in `doc/idea-v1-decisions.md`.

### 6. [Medium][Architecture] Autosave seam has no snapshot payload and no restore path
- **Location:** `scripts/TimeManager.gd:462-465`, `:129-138`, `:372-375`; `scripts/SaveManager.gd:16-17`
- **Evidence:** `_request_autosave()` calls `SaveManager.autosave()` with no arguments, and `start_day()` calls `_reset_records()` and always enters `PERIOD1`. There is no API exposing `_state`, `_phase_elapsed`, `_attendance`, `_grades`, `_roster`, or `_player_absent`.
- **Problem:** Ticket 017 cannot restore a mid-day save; it can only restart the day from scratch. The design says "self-contained records in TimeManager", which implies TimeManager is their owner and must expose them.
- **Recommendation:** Either add `get_day_snapshot()` / `restore_day_snapshot(snapshot)` now and pass the snapshot to `SaveManager.autosave(snapshot)`, or — to keep 011's scope — record explicitly in `doc/idea-v1-decisions.md` that ticket 017 owns the snapshot/restore API and must add it before implementing save/load. Do not silently leave the gap.

### 7. [Low][Architecture] Default roster is keyed by template id, so two NPCs from one template would collapse
- **Location:** `scripts/TimeManager.gd:207-216`, `scripts/TimeManager.gd:451-459`
- **Evidence:** `set_roster()` (line 214) and `_ensure_roster()` (line 457) both skip duplicate ids, and attendance/grades/stats are keyed by that same id. Ticket 012 (`doc/tickets/012-npc-spawning-scheduling.md:3,12`) requires 3–5 NPCs from templates and per-NPC attendance.
- **Problem:** Two instances of the same template cannot have separate attendance/grade records if the default roster path is used.
- **Recommendation:** Document that `set_roster()` must be called with stable **instance** ids (not template ids) once ticket 012 spawns NPCs; keep template ids only for `_stats_for()` lookup. The existing API already accepts arbitrary ids, so this is a documentation/contract fix, not new machinery in 011.

### 8. [Low][Bug] `_finish_skip()` fallback can duplicate DayEnd side effects
- **Location:** `scripts/TimeManager.gd:384-390`
- **Evidence:** `_complete_and_advance()` already calls `_enter_state(next)` at line 357; the drift guard at 389-390 calls `_enter_state(target)` again if the state differs. `target` came from the same `_next_state()` used by `_complete_and_advance()`, so the branch is dead today but becomes reachable through the `skip_simulation_requested` hook intended for tickets 013/016.
- **Problem:** A hook listener that changes state during the pause could re-emit `state_changed`, `day_ended`, autosave, `manual_save_requested`, or `day_started` for one skip.
- **Recommendation:** Delete the fallback and trust the single transition path; if re-entrancy is a real concern, guard state mutation during the skip beat instead.

### 9. [Low][Bug] `get_phase_duration()` reports a duration for BREAK even though the clock is halted
- **Location:** `scripts/TimeManager.gd:161-163`, `scripts/TimeManager.gd:333-334`
- **Evidence:** `advance()` returns early for BREAK at line 162, but `_duration_for(BREAK)` returns `transition_duration_sec` (1.0) at 333-334.
- **Problem:** The inspection API contradicts actual behavior for a public state.
- **Recommendation:** Return `0.0` for `DayState.BREAK` in `_duration_for()`.

### 10. [Low][Process] Ticket 011 status/checkboxes are stale and no regression suite remains in the repo
- **Location:** `doc/tickets/011-day-state-machine.md:7-16`
- **Evidence:** Status is still `ready-for-agent` and all eight checkboxes are `- [ ]`, while `doc/tickets/010-modloader.md:7-16` uses `Status: done` with all boxes ticked. The 32/32 verification and the reproductions above used temporary scripts that were deleted.
- **Problem:** The ticket file does not reflect completion, and none of the four behaviors missed by the original 32-check run is covered by a reproducible artifact.
- **Recommendation:** After the fixes above are verified, set `Status: done` and tick all eight checkboxes. Either commit a minimal headless regression suite covering large-delta carry, rollover `day_started` state, roster override, and break-mid-period recording, or explicitly record those verification results in the plan's `progress.md`.

## Areas with no findings

- Grade math (`scripts/TimeManager.gd:408-427`) matches the design formula exactly for NPCs.
- DayEnd signal order (`state_changed` → `day_ended` → guarded `SaveManager.autosave()` → `manual_save_requested("day_end")`) matches the design.
- Skipped classes still record attendance/grade with perfect NPC attendance (reproduced).
- Day loop `NEXTDAY → PERIOD1` wraps without crashing over repeated days.
- `ModLoader` registry API usage (`get_resource`, `get_all`, `TYPE_CHARACTER`) matches `scripts/ModLoader.gd:81-96`.
