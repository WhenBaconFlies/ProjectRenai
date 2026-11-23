## TimeManager
##
## Global singleton (autoload) owning the day clock and the explicit day state
## machine: Period1 → FreeTime1 → … → Period4 → DayEnd → Save → NextDay.
##
## Responsibilities (ticket 011):
##   - advance the real-time clock in _process(delta) through a public
##     advance(delta) seam that headless tests can drive deterministically;
##   - record per-period attendance for the player and registered NPCs
##     (NPCs are always present in v1);
##   - compute a small grade/stat bonus from attendance + INT/WIS, stored in
##     self-contained records and emitted for later tickets to apply;
##   - expose skip(), which jumps to the next phase boundary without simulating
##     the skipped time, but emits a simulation hook and briefly halts the clock
##     so tickets 013/016 (and a future loading UI) can hook a fast-forward in;
##   - signal DayEnd so SaveManager can autosave and a manual save can be offered.
##
## No NpcInstance/PlayerInstance schema exists yet (012+), so attendance and
## grade records are keyed by character id and stats come from an injectable
## provider that defaults to CharacterTemplate INT/WIS via the ModLoader.
extends Node

## --- Day states -------------------------------------------------------------

## Explicit day states. BREAK is a separate state deliberately outside the
## normal v1 sequence (weekend/season break screens are deferred).
enum DayState {
	IDLE,
	PERIOD1,
	FREETIME1,
	PERIOD2,
	FREETIME2,
	PERIOD3,
	FREETIME3,
	PERIOD4,
	DAYEND,
	SAVE,
	NEXTDAY,
	BREAK,
}

## The normal in-game day order, repeated after NEXTDAY.
const DAY_SEQUENCE = [
	DayState.PERIOD1, DayState.FREETIME1,
	DayState.PERIOD2, DayState.FREETIME2,
	DayState.PERIOD3, DayState.FREETIME3,
	DayState.PERIOD4,
	DayState.DAYEND, DayState.SAVE, DayState.NEXTDAY,
]

## --- Signals ---------------------------------------------------------------

## Emitted when a new day begins (start_day or after NEXTDAY).
signal day_started(day: int)
## Emitted on every state entry, with (new_state, old_state) as DayState values.
signal state_changed(new_state: int, old_state: int)
## Emitted when a class period completes, with its attendance + grade records.
signal period_completed(period: int, attendance: Dictionary, grade: Dictionary)
## Emitted on entering DayEnd (before the save hooks fire).
signal day_ended(day: int)
## Emitted at DayEnd so a deferred UI can offer a manual save.
signal manual_save_requested(reason: String)
## Hook for a future fast-forward: nothing simulates in 011, but later tickets
## can listen and run a quick pass of AI/interactions while the clock is held.
signal skip_simulation_requested(from_state: int, to_state: int, skipped_duration: float)
## Emitted when the separate (non-v1) break state is entered.
signal break_day_started(day: int)

## --- Tunable configuration -------------------------------------------------

## Seconds a class period lasts on the real-time clock.
@export var period_duration_sec: float = 45.0
## Seconds of free roam between classes.
@export var free_time_duration_sec: float = 30.0
## Seconds spent in the short DayEnd / Save / NextDay transition phases.
@export var transition_duration_sec: float = 1.0
## Brief clock-halted beat on skip, giving listeners a chance to fast-forward.
@export var skip_pause_sec: float = 0.5

## Character id representing the player in attendance/grade records.
@export var player_character_id: String = "player"
## Template id used to read the player's default INT/WIS from the ModLoader.
@export var player_template_id: String = ""
## Fallback template resource for player INT/WIS when no registry entry exists
## (base characters in res://resources/ are loaded directly, not modded in).
@export var player_template_path: String = "res://resources/characters/char_alex.tres"

## Grade stub constants — "small stat bonus" is intentionally tunable.
@export var grade_bonus_cap: int = 3
@export var grade_bonus_divisor: int = 20

## --- Runtime state ---------------------------------------------------------

var _state: int = DayState.IDLE
var _running: bool = false
var _day_number: int = 0
var _phase_elapsed: float = 0.0

## period (1..4) -> { character id -> bool (present) }
var _attendance: Dictionary = {}
## period (1..4) -> { character id -> { present, score, letter, bonus } }
var _grades: Dictionary = {}

## Character ids recorded each period: player first, then NPCs.
var _roster: Array = []
var _player_id: String = "player"
var _player_absent: bool = false

## Optional (character_id: String) -> { intelligence: int, wisdom: int }.
var _stats_provider: Callable = Callable()

## Skip bookkeeping: the clock is halted while a skip beat is pending.
var _skip_in_progress: bool = false
var _skip_pause_remaining: float = 0.0

## day_started is emitted on entry to PERIOD1 so subscribers always observe a
## period state, whether the day began via start_day() or a NEXTDAY rollover.
var _pending_day_started: bool = false

## Break entry/exit context: an interrupted class is recorded and resumes at
## the phase that would have followed it, rather than restarting the day.
var _state_before_break: int = DayState.IDLE
var _elapsed_before_break: float = 0.0


func _ready() -> void:
	# The day is started by the Game scene's _ready(), once the scene (and its
	# listeners) exists. Honour the exported player id on the default path;
	# set_roster() remains the explicit override.
	_player_id = player_character_id if not player_character_id.is_empty() else "player"
	_reset_records()


func _process(delta: float) -> void:
	if _running:
		advance(delta)


## --- Public clock / lifecycle API -----------------------------------------

## Begin `day_number` at Period1 with empty per-day records.
func start_day(day_number: int = 1) -> void:
	_day_number = maxi(1, day_number)
	_reset_records()
	_ensure_roster()
	_running = true
	_skip_in_progress = false
	_skip_pause_remaining = 0.0
	_phase_elapsed = 0.0
	_pending_day_started = true
	_state_before_break = DayState.IDLE
	_elapsed_before_break = 0.0
	_enter_state(DayState.PERIOD1)


## Halt the clock. State and records are left intact for inspection/restart.
func stop_day() -> void:
	_running = false
	_skip_in_progress = false
	_skip_pause_remaining = 0.0


## Advance the day clock by `delta` seconds. _process calls this every frame;
## tests call it with large deltas to cross phase boundaries deterministically.
func advance(delta: float) -> void:
	if not _running or delta <= 0.0:
		return

	# A pending skip holds the phase clock while the fast-forward hook plays.
	if _skip_in_progress:
		_skip_pause_remaining -= delta
		if _skip_pause_remaining <= 0.0:
			_finish_skip()
		return

	# Break days are a separate, paused state until end_break_day() is called.
	if _state == DayState.BREAK:
		return

	var duration: float = _duration_for(_state)
	if duration <= 0.0:
		_complete_and_advance()
		return

	_phase_elapsed += delta
	var guard: int = 0
	while _phase_elapsed >= duration:
		# _enter_state() resets _phase_elapsed, so hold the remainder locally
		# and restore it afterwards; otherwise large deltas lose all carry.
		var carry: float = _phase_elapsed - duration
		_complete_and_advance()
		if not _running:
			return
		_phase_elapsed += carry
		duration = _duration_for(_state)
		guard += 1
		# Zero-duration states could otherwise cycle forever on a huge delta.
		if duration <= 0.0 or guard >= 64:
			break


## Jump to the next phase boundary. The skipped time is not simulated; instead
## a hook is emitted and the clock is held for skip_pause_sec before the normal
## transition logic runs (so a skipped class still records attendance/grade).
func skip() -> void:
	if not _running or _skip_in_progress:
		return
	if _state == DayState.IDLE or _state == DayState.BREAK:
		return

	var target: int = _next_state()
	var skipped_duration: float = maxf(0.0, _duration_for(_state) - _phase_elapsed)
	_skip_in_progress = true
	_skip_pause_remaining = maxf(0.0, skip_pause_sec)
	skip_simulation_requested.emit(_state, target, skipped_duration)


## True while a skip's brief fast-forward beat is holding the clock.
func is_skipping() -> bool:
	return _skip_in_progress


## --- Roster / stats seams -------------------------------------------------

## Set the ids attendance is recorded for. `npc_ids` MUST be stable instance
## ids (not template ids) once ticket 012 spawns multiple NPCs from one
## template — records are keyed by id, so duplicate ids would collapse.
## NPCs are always present in v1.
func set_roster(player_id: String, npc_ids: Array = []) -> void:
	_player_id = player_id if not player_id.is_empty() else player_character_id
	_roster.clear()
	if not _roster.has(_player_id):
		_roster.append(_player_id)
	for raw_id in npc_ids:
		var id: String = str(raw_id)
		if id.is_empty() or id == _player_id or _roster.has(id):
			continue
		_roster.append(id)


## Provide (character_id) -> { intelligence, wisdom }. Pass Callable() to clear.
func set_stats_provider(provider: Callable) -> void:
	_stats_provider = provider if provider.is_valid() else Callable()


## Test seam: mark the player absent for the current day's remaining periods.
func record_player_absent() -> void:
	_player_absent = true


## Test seam: mark the player present again.
func record_player_present() -> void:
	_player_absent = false


## --- Break state (separate, not exercised in v1) --------------------------

## Enter the separate break-day state. The clock pauses until end_break_day().
func start_break_day() -> void:
	if not _running or _state == DayState.BREAK:
		return
	if is_period_state(_state):
		# Treat the interrupted class as finished so its attendance/grade is
		# not lost, and resume at the phase that would have followed it.
		_record_period(period_number_for(_state))
		_state_before_break = _next_state()
		_elapsed_before_break = 0.0
	else:
		_state_before_break = _state
		_elapsed_before_break = _phase_elapsed
	_enter_state(DayState.BREAK)


## Leave the break state and resume the phase that was interrupted.
func end_break_day() -> void:
	if _state != DayState.BREAK:
		return
	var target: int = _state_before_break
	if target == DayState.IDLE:
		target = DayState.PERIOD1
	_enter_state(target)
	_phase_elapsed = _elapsed_before_break


## --- Inspection API -------------------------------------------------------

func get_state() -> int:
	return _state


## Human-readable state name, e.g. "PERIOD1" (useful in logs/tests).
func get_state_name() -> String:
	var keys := DayState.keys()
	if _state >= 0 and _state < keys.size():
		return str(keys[_state])
	return "UNKNOWN"


func get_current_period() -> int:
	return period_number_for(_state)


func get_phase_elapsed() -> float:
	return _phase_elapsed


func get_phase_duration() -> float:
	return _duration_for(_state)


func get_day_number() -> int:
	return _day_number


func is_running() -> bool:
	return _running


func get_roster() -> Array:
	return _roster.duplicate()


func get_attendance() -> Dictionary:
	return _attendance.duplicate(true)


func get_grades() -> Dictionary:
	return _grades.duplicate(true)


## Summed stat bonus per character id across all recorded periods of this day.
func get_stat_bonuses() -> Dictionary:
	var totals: Dictionary = {}
	for period_grades in _grades.values():
		for id in (period_grades as Dictionary).keys():
			var bonus: int = int((period_grades as Dictionary)[id].get("bonus", 0))
			totals[id] = int(totals.get(id, 0)) + bonus
	return totals


## Full per-day state for ticket 017 to persist. Values are deep-copied so a
## caller cannot mutate live records through the snapshot.
func get_day_snapshot() -> Dictionary:
	return {
		"day": _day_number,
		"state": _state,
		"phase_elapsed": _phase_elapsed,
		"attendance": _attendance.duplicate(true),
		"grades": _grades.duplicate(true),
		"roster": _roster.duplicate(),
		"player_id": _player_id,
		"player_absent": _player_absent,
	}


## Restore a snapshot produced by get_day_snapshot(). Returns false for a
## malformed payload. Used by ticket 017's save/load; never partially applies.
func restore_day_snapshot(snapshot: Dictionary) -> bool:
	if not snapshot.has("day") or not snapshot.has("state"):
		return false
	_day_number = maxi(1, int(snapshot.get("day", 1)))
	_state = int(snapshot.get("state", DayState.PERIOD1))
	_phase_elapsed = maxf(0.0, float(snapshot.get("phase_elapsed", 0.0)))
	var attendance: Variant = snapshot.get("attendance", {})
	var grades: Variant = snapshot.get("grades", {})
	var roster: Variant = snapshot.get("roster", [])
	_attendance = (attendance as Dictionary).duplicate(true) if attendance is Dictionary else {}
	_grades = (grades as Dictionary).duplicate(true) if grades is Dictionary else {}
	_roster = (roster as Array).duplicate() if roster is Array else []
	_player_id = str(snapshot.get("player_id", player_character_id))
	_player_absent = bool(snapshot.get("player_absent", false))
	_skip_in_progress = false
	_skip_pause_remaining = 0.0
	_pending_day_started = false
	_running = true
	return true


func is_period_state(state: int) -> bool:
	return period_number_for(state) > 0


## Map a period state (PERIOD1..PERIOD4) to its 1-based number, else 0.
func period_number_for(state: int) -> int:
	match state:
		DayState.PERIOD1:
			return 1
		DayState.PERIOD2:
			return 2
		DayState.PERIOD3:
			return 3
		DayState.PERIOD4:
			return 4
		_:
			return 0


## --- Internals -------------------------------------------------------------

func _duration_for(state: int) -> float:
	match state:
		DayState.PERIOD1, DayState.PERIOD2, DayState.PERIOD3, DayState.PERIOD4:
			return maxf(0.0, period_duration_sec)
		DayState.FREETIME1, DayState.FREETIME2, DayState.FREETIME3:
			return maxf(0.0, free_time_duration_sec)
		DayState.DAYEND, DayState.SAVE, DayState.NEXTDAY:
			return maxf(0.0, transition_duration_sec)
		DayState.BREAK:
			# The clock is paused in BREAK; reporting a duration would be a lie.
			return 0.0
		_:
			return 0.0


## The state that follows `state` in the normal sequence.
func _next_state() -> int:
	var index: int = DAY_SEQUENCE.find(_state)
	if index == -1:
		return DayState.IDLE
	return int(DAY_SEQUENCE[(index + 1) % DAY_SEQUENCE.size()])


## Complete the current phase (recording a class if we are leaving one) and
## enter the next state. Shared by natural clock advance and by skip().
func _complete_and_advance() -> void:
	if is_period_state(_state):
		_record_period(period_number_for(_state))
	var next: int = _next_state()
	if next == DayState.IDLE:
		stop_day()
		return
	_enter_state(next)


## Single transition point: updates state/elapsed, emits signals, and applies
## the side effects of DayEnd / NextDay / Break entry.
func _enter_state(next_state: int) -> void:
	var old: int = _state
	_state = next_state
	_phase_elapsed = 0.0
	state_changed.emit(_state, old)

	match _state:
		DayState.PERIOD1:
			if _pending_day_started:
				_pending_day_started = false
				day_started.emit(_day_number)
		DayState.DAYEND:
			day_ended.emit(_day_number)
			_request_autosave()
			manual_save_requested.emit("day_end")
		DayState.NEXTDAY:
			_day_number += 1
			_reset_records()
			_pending_day_started = true
		DayState.BREAK:
			break_day_started.emit(_day_number)
		_:
			pass


## Finish a pending skip: run the shared completion logic, then guard against
## any drift between the predicted target and the actual next state.
func _finish_skip() -> void:
	_skip_in_progress = false
	_skip_pause_remaining = 0.0
	# _complete_and_advance() is the single transition path; never call
	# _enter_state() again here (it would replay DayEnd/NEXTDAY side effects).
	_complete_and_advance()


func _record_period(period: int) -> void:
	if period <= 0:
		return
	var attendance: Dictionary = {}
	var grades: Dictionary = {}
	for id in _roster:
		# NPCs are always present in v1; only the player can be marked absent.
		var present: bool = (id != _player_id) or not _player_absent
		attendance[id] = present
		grades[id] = _compute_grade(id, present)
	_attendance[period] = attendance
	_grades[period] = grades
	period_completed.emit(period, attendance.duplicate(true), grades.duplicate(true))


func _compute_grade(id: String, present: bool) -> Dictionary:
	if not present:
		return {"present": false, "score": 0, "letter": "ABSENT", "bonus": 0}
	var stats: Dictionary = _stats_for(id)
	var total: int = clampi(int(stats.get("intelligence", 0)), 0, 100) + clampi(int(stats.get("wisdom", 0)), 0, 100)
	var score: int = clampi(60 + total / 2, 0, 100)
	var bonus: int = clampi(1 + total / maxi(1, grade_bonus_divisor), 0, maxi(0, grade_bonus_cap))
	return {"present": true, "score": score, "letter": _letter_for(score), "bonus": bonus}


func _letter_for(score: int) -> String:
	if score >= 90:
		return "A"
	if score >= 75:
		return "B"
	if score >= 60:
		return "C"
	if score >= 40:
		return "D"
	return "F"


func _stats_for(id: String) -> Dictionary:
	if _stats_provider.is_valid():
		var provided: Variant = _stats_provider.call(id)
		if provided is Dictionary:
			return provided

	# Default: read INT/WIS from the authored CharacterTemplate in the registry.
	var template_id: String = player_template_id if id == _player_id else id
	var resource: Resource = ModLoader.get_resource(ModLoader.TYPE_CHARACTER, template_id)
	if resource == null and id == _player_id:
		resource = ModLoader.get_resource(ModLoader.TYPE_CHARACTER, id)
	if resource == null and id == _player_id and not player_template_path.is_empty() and ResourceLoader.exists(player_template_path):
		resource = ResourceLoader.load(player_template_path)
	if resource is CharacterTemplate:
		return {
			"intelligence": (resource as CharacterTemplate).intelligence,
			"wisdom": (resource as CharacterTemplate).wisdom,
		}
	return {"intelligence": 0, "wisdom": 0}


## Populate a default roster from the ModLoader registry when none was set, so
## NPC perfect attendance is observable without hard-coding character ids.
func _ensure_roster() -> void:
	if not _roster.is_empty():
		return
	_roster.append(_player_id)

	# Base character templates are in the registry as of ticket 012, so the
	# player's own template must not become a phantom NPC attendee here.
	var player_template_ids: Dictionary = {}
	if not player_template_id.is_empty():
		player_template_ids[player_template_id] = true
	if not player_template_path.is_empty() and ResourceLoader.exists(player_template_path):
		var player_template := ResourceLoader.load(player_template_path) as CharacterTemplate
		if player_template != null and not player_template.id.is_empty():
			player_template_ids[player_template.id] = true

	for resource in ModLoader.get_all(ModLoader.TYPE_CHARACTER):
		var id: String = str(resource.get("id"))
		if id.is_empty() or id == _player_id or player_template_ids.has(id) or _roster.has(id):
			continue
		_roster.append(id)


## Deferred to a guarded call so ticket 017 can replace the SaveManager stub.
func _request_autosave() -> void:
	if SaveManager != null and SaveManager.has_method("autosave"):
		SaveManager.call("autosave", get_day_snapshot())


func _reset_records() -> void:
	_attendance.clear()
	_grades.clear()
	_player_absent = false
