# 011 — Day state machine: short design

Companion to `doc/tickets/011-day-state-machine.md`. Records the agreed approach
before implementation; the durable decisions also live in `doc/idea-v1-decisions.md`.

## Intent / why

The v1 slice needs a day loop that structures play into four class periods with
free roam between them, can be skipped for playtesting, and produces attendance +
grade data for the stats pipeline. `TimeManager` is currently an empty autoload
stub; this ticket fills it in. One-day vertical slice — no menus, no academic
system, no break-day screens.

## Goals

1. An explicit enum state machine: `PERIOD1 → FREETIME1 → PERIOD2 → FREETIME2 → PERIOD3 → FREETIME3 → PERIOD4 → DAYEND → SAVE → NEXTDAY → PERIOD1…`
2. A real-time clock (`_process(delta)`) drives transitions; durations are exported and tunable.
3. `skip()` jumps to the next phase boundary instantly, firing the same transition logic (no intermediate ticking / simulation).
4. Attendance recorded per period for the player and NPCs; NPCs are always present in v1.
5. A grade stub computes a score + a small stat bonus from attendance and INT/WIS, stored in records and emitted for later tickets to apply.
6. `DayEnd` calls an autosave stub hook and emits a manual-save-request signal.
7. `BREAK` exists as a separate state with explicit entry/exit, not part of the normal v1 sequence.

## Non-goals / anti-goals

- No real save/load implementation (ticket 017), no instance schema (012+), no NPC spawning/AI (012/013), no UI widgets (menus deferred).
- No day-end summary screen — signal only.
- Do not simulate skipped time (no movement, no NPC AI ticks inside `skip()`).
- Do not hard-code a real-world clock or calendar; v1 is a loop driven by elapsed seconds.

## Constraints / seams

- GDScript, autoload in `project.godot` (already registered). No new `class_name` (avoids autoload shadowing).
- `SaveManager` is a stub: add a log-only `autosave()` hook for 017 to replace.
- No `NpcInstance`/`PlayerInstance` yet: attendance/grade records are self-contained in `TimeManager`, keyed by character id. A `Callable` stats provider defaults to `CharacterTemplate` INT/WIS from the `ModLoader` registry; later tickets inject instance-backed stats.
- Roster (player id + NPC ids) is settable; default falls back to `ModLoader` character ids so NPC perfect attendance is observable without hard-coding ids.

## Approaches considered

- **A — State machine inside TimeManager (chosen).** Matches the spec ("TimeManager — day clock … drives the day state machine"), one file, simplest seam. Signals notify other systems.
- **B — Separate `DayStateMachine` Resource owned by TimeManager.** Cleaner separation but a second class/file with no consumer in v1; deferred if the loop grows.
- **C — Timer nodes per phase.** More scene wiring and frame-timer drift; rejected in favour of one `_process` accumulator with an explicit `advance(delta)` test seam.

## How it will work

- **Clock:** `_phase_elapsed += delta` in `advance(delta)`; transition when it reaches the current phase duration and carry the remainder into the next phase (a large delta can cross several boundaries). `_process(delta)` calls `advance(delta)` while running. Exported defaults: 45 s per class, 30 s free time, ~1 s for DayEnd/Save/NextDay transitions.
- **Transitions:** a single `_enter_state(next)` updates state, resets elapsed, and emits `state_changed`. Leaving a `PERIODx` state calls `_record_period(period)` — the one place attendance + grade are written, so natural completion and `skip()` share it.
- **Skip (with simulation seam — user-approved change):** `skip()` emits `skip_simulation_requested(from_state, to_state, skipped_duration)` and starts a short, configurable pause beat (`skip_pause_sec`, default ~0.5 s) during which the phase clock is halted. When the beat expires, `_complete_and_advance()` (fire period-change logic if in a class) runs and enters the next state with elapsed reset. In free time, skip jumps to the next class. No AI/movement/interaction simulation and no loading UI are implemented in 011 — the signal + pause beat are the hook for tickets 013/016 and the deferred UI to run fast-forward later. Re-entrant `skip()` calls while a beat is pending are ignored. State order and attendance records are unchanged.
- **Attendance:** `_attendance[period] = { id: true }` for every roster id; NPCs always true (perfect v1 attendance). Player present unless explicitly marked absent via the test seam.
- **Grade stub:** per period, per id: `present`, `score`, `letter`, `bonus`. With present stats `intelligence`, `wisdom`: `score = clampi(60 + (int+wis)/2, 0, 100)`, `bonus = clampi(1 + (int+wis)/20, 0, 3)` (0 when absent). `get_stat_bonuses()` aggregates per id across periods. Constants are exported/tunable.
- **Save seam:** on `DAYEND` entry call guarded `SaveManager.autosave(snapshot)` with `get_day_snapshot()` and emit `manual_save_requested("day_end")`; emit `day_ended(day)`. `restore_day_snapshot()` gives ticket 017 a resume path. No save logic in 011.
- **Break:** `BREAK` in the enum with `start_break_day()`/`end_break_day()` and a `break_day_started` signal; deliberately not in the normal sequence. Entering it mid-class records the interrupted period and exiting resumes at the following phase.
- **Day start:** `GameManager.start_fresh_day()` switches to `Game.tscn`; the new `Game.gd` root script calls `TimeManager.start_day(1)` in its own `_ready()` so scene listeners are connected first. `day_started` always fires on `PERIOD1` entry.
- **Public/test surface:** `start_day()`, `stop_day()`, `advance(delta)`, `skip()`, `is_skipping()`, `set_roster()`, `set_stats_provider()`, `record_player_absent()`, `get_state()/get_state_name()`, `get_current_period()`, `get_attendance()/get_grades()/get_stat_bonuses()`, `get_day_number()`, `get_day_snapshot()/restore_day_snapshot()`.

## Verification

Headless Godot 4.2.1 script covering all 8 acceptance checkboxes (state order, clock advance, skip boundary, per-period attendance, grade bonus math, NPC perfect attendance, DayEnd autosave + prompt signals, break state), plus a default-launch smoke check that `Game.tscn` loads without parse/runtime errors. Temporary verification scripts removed after the run. Code-review-expert report placed in `doc/code-review/`. No GitHub push without final user approval.
