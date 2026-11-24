## DayLoopIntegrationTest
##
## Persistent headless acceptance harness for ticket 018. It drives the REAL
## day-loop seam -- DebugStart.tscn -> GameManager -> Game.tscn -- and asserts all
## ten v1 acceptance criteria through observable behaviour (signals, scene state,
## save files and resources). A few read-only probes of internal state are used
## where no public accessor exists; they never drive production behaviour.
##
## The clock is stopped and advanced manually with TimeManager.advance() so a
## ~230 s default day completes in a few headless frames. Phase durations are
## shortened for the same reason; that changes pacing, never the state sequence.
##
## A child of /root (added by IntegrationBootstrap), so scene changes do not free
## it. Prints ALL_018_CHECKS_PASSED only when every assertion passed.
extends Node


## --- Test configuration -----------------------------------------------------

## Root of the synthetic mod tree used for mod-discovery checks.
const MODS_TEST_ROOT: String = "user://integration_mods/"
## Named slot used for the save/reload part of the day-loop seam.
const INTEGRATION_SLOT: String = "integration"
## Slot carrying an instance whose template id cannot be resolved.
const MISSING_TEMPLATE_SLOT: String = "missing_template"

var _passed: int = 0
var _failed: int = 0

## The currently live Game scene root (re-acquired after every scene change).
var _game: Node = null

## Signals captured from the real systems.
var _states: Array = []
var _resolved: Array = []
var _initiations: Array = []

## State captured before a reload, for the "restore identically" assertion.
var _before_reload: Dictionary = {}

## User saves are shared with normal play. Back up an existing autosave so the
## harness can start from a clean fixture without destroying a developer's data.
var _had_autosave: bool = false
var _autosave_backup: PackedByteArray = PackedByteArray()


func _ready() -> void:
	# Install the clock listener before DebugStart/Game emit anything.
	if not TimeManager.state_changed.is_connected(_on_state_changed):
		TimeManager.state_changed.connect(_on_state_changed)
	# Deferred so the bootstrap's scene-change request is queued after this
	# coroutine's first await but before any phase is advanced.
	call_deferred("_run")


## --- Entry sequence ---------------------------------------------------------

func _run() -> void:
	_prepare_save_fixture()
	_configure_clock()
	_check(_verify_code_comments(), "AC10: scripts and functions are documented")

	_game = await _wait_for_game()
	if _game == null:
		_check(false, "AC1: DebugStart -> Game scene loaded")
		_finish()
		return
	_check(true, "AC1: DebugStart -> Game scene loaded")

	_configure_game()
	_wire_game_signals()
	_check(_states.has(TimeManager.DayState.PERIOD1), "AC1: day starts in PERIOD1")
	_check_spawn()
	await _check_movement()
	await _check_player_dialogue()
	_check_skip_and_attendance()
	await _check_npc_initiation()
	await _check_full_day_and_autosave()
	await _check_save_reload()
	_check_mods()
	await _check_missing_template_recovery()

	_restore_environment()
	_finish()


## Shorten every phase and stop the autoload's automatic clock so advance()
## is the single, deterministic driver of the state machine.
func _configure_clock() -> void:
	TimeManager.set_process(false)
	TimeManager.period_duration_sec = 0.2
	TimeManager.free_time_duration_sec = 0.2
	TimeManager.transition_duration_sec = 0.2
	TimeManager.skip_pause_sec = 0.05


## Tune the live Game instance for a fast but observable free time. Class travel
## is disabled here: forced destinations would (correctly) block NPC initiation
## and this harness is checking initiation, not the ticket-013 walk.
func _configure_game() -> void:
	_game.set("npc_initiation_enabled", true)
	_game.set("npc_initiation_check_interval_sec", 0.05)
	_game.set("npc_initiation_hold_sec", 0.05)
	_game.set("npc_initiation_cooldown_sec", 0.1)
	_game.set("class_travel_lead_sec", 0.0)
	_game.set("show_relationship_feedback", true)


func _wire_game_signals() -> void:
	if not _game.is_connected("dialogue_resolved", Callable(self, "_on_dialogue_resolved")):
		_game.connect("dialogue_resolved", Callable(self, "_on_dialogue_resolved"))
	if not _game.is_connected("npc_interaction_started", Callable(self, "_on_npc_interaction_started")):
		_game.connect("npc_interaction_started", Callable(self, "_on_npc_interaction_started"))


## --- AC1: spawn -------------------------------------------------------------

func _check_spawn() -> void:
	var player: Node2D = _game.get_node_or_null("Player") as Node2D
	var npcs_root: Node = _game.get_node_or_null("Npcs")
	var npc_count: int = npcs_root.get_child_count() if npcs_root != null else 0
	var roster: Array = TimeManager.get_roster()
	_check(player != null, "AC1: player spawned")
	_check(npc_count == 4, "AC1: four NPCs spawned from template ids")
	_check(roster.size() == 5, "AC1: roster holds player + four stable instance ids")


## --- AC2: move, E, pool, resolution and feedback ----------------------------

func _check_movement() -> void:
	var player: Node2D = _game.get_node_or_null("Player") as Node2D
	if player == null:
		_check(false, "AC2: player movement (no player node)")
		return
	# Wait out Player's deferred spawn snap before measuring.
	await get_tree().process_frame
	var start_x: float = player.global_position.x
	Input.action_press("move_right")
	for _i in range(18):
		await get_tree().physics_frame
	Input.action_release("move_right")
	var moved: bool = player.global_position.x > start_x + 2.0
	_check(moved, "AC2: player moves right on input (%.1f -> %.1f)" % [start_x, player.global_position.x])


func _check_player_dialogue() -> void:
	var npcs_root: Node = _game.get_node_or_null("Npcs")
	var player: Node2D = _game.get_node_or_null("Player") as Node2D
	var pool_ui: Node = _game.get_node_or_null("DialogueLayer/DialoguePoolUI")
	if npcs_root == null or npcs_root.get_child_count() == 0 or player == null or pool_ui == null:
		_check(false, "AC2: dialogue pool opened (missing scene nodes)")
		return

	# Arrange: put the player inside InteractionComponent's proximity radius.
	# This is test setup; the behaviour under test is the E -> pool -> pick path.
	var target: Node = npcs_root.get_child(0)
	player.global_position = target.global_position + Vector2(12.0, 0.0)
	# The proximity Area2D needs physics ticks to refresh its overlap set.
	for _i in range(4):
		await get_tree().physics_frame
	var interaction: Node = _game.get_node_or_null("Player/InteractionComponent")
	if interaction == null or not bool(interaction.call("is_enabled")):
		_check(false, "AC2: E opens the dialogue pool (no interaction component)")
		return

	# Headless Godot does not deliver parse_input_event() to _unhandled_input, so
	# dispatch a real InputEventKey straight to the component's handler. That
	# still exercises the exact E-key -> action lookup -> nearest-NPC emit path.
	_send_key_to(interaction, KEY_E)
	for _i in range(3):
		await get_tree().process_frame
	_check(bool(pool_ui.call("is_open")), "AC2: E opens the dialogue pool")

	var pool: Array = pool_ui.get("_topics") as Array
	var pool_size: int = pool.size()
	_check(pool_size >= 3 and pool_size <= 5, "AC2: pool has 3-5 topics (got %d)" % pool_size)

	var resolved_before: int = _resolved.size()
	_send_key_to(pool_ui, KEY_1)
	for _i in range(3):
		await get_tree().process_frame
	_check(_resolved.size() > resolved_before, "AC2: topic selection emits a resolver result")
	if _resolved.is_empty():
		_check(false, "AC2: meters and mood changed with feedback")
		return
	var result: Dictionary = _resolved[_resolved.size() - 1]
	var before: Dictionary = result.get("before", {})
	var after: Dictionary = result.get("after", {})
	var changed: bool = true
	for party in ["initiator", "target"]:
		for field in ["familiarity", "affection", "mood"]:
			if int(_party_field(after, party, field)) == int(_party_field(before, party, field)):
				changed = false
	var feedback: Node = _game.get_node_or_null("FeedbackLayer/InteractionFeedbackUI")
	_check(changed, "AC2: both parties' familiarity, affection and mood change")
	_check(feedback != null and bool(feedback.call("is_open")), "AC2: feedback panel is shown")
	_check(bool(pool_ui.call("is_open")) == false, "AC2: pool closes after selection")


## --- AC8 / AC9: skip, attendance and grade stub -----------------------------

func _check_skip_and_attendance() -> void:
	_check(TimeManager.get_state_name() == "PERIOD1", "AC8: skip starts from PERIOD1")
	TimeManager.skip()
	_check(TimeManager.is_skipping(), "AC8: skip halts the clock for a beat")
	TimeManager.advance(0.1)
	_check(TimeManager.get_state_name() == "FREETIME1", "AC8: skip lands on FREETIME1")

	var attendance: Dictionary = TimeManager.get_attendance()
	var grades: Dictionary = TimeManager.get_grades()
	var period_one: Dictionary = attendance.get(1, {})
	var grade_one: Dictionary = grades.get(1, {})
	_check(period_one.size() == 5, "AC9: attendance recorded for player + 4 NPCs")
	_check(grade_one.size() == 5, "AC9: grade stub recorded for every roster id")
	var sample: Dictionary = grade_one.get("player", {})
	_check(
		sample.has("score") and sample.has("letter") and sample.has("bonus"),
		"AC9: grade record has score, letter and stat bonus"
	)


## --- AC3: NPC-initiated interaction during free time ------------------------

func _check_npc_initiation() -> void:
	if TimeManager.get_state_name() != "FREETIME1":
		_check(false, "AC3: NPC initiates during free time (wrong phase)")
		return
	_initiations.clear()
	# Budget by wall time, not frame count: headless frame rate varies by machine,
	# and Game.gd accumulates real delta for its 0.05 s check interval.
	var start_ms: int = Time.get_ticks_msec()
	var frames: int = 0
	while _initiations.is_empty() and frames < 2000 and Time.get_ticks_msec() - start_ms < 5000:
		await get_tree().process_frame
		frames += 1
	_check(not _initiations.is_empty(), "AC3: an outgoing NPC initiates an interaction")
	if not _initiations.is_empty():
		var entry: Array = _initiations[0]
		_check(entry.size() == 3, "AC3: initiation carries topic id and both roster ids")


## --- AC1 (full day) + autosave ----------------------------------------------

func _check_full_day_and_autosave() -> void:
	_check(TimeManager.get_state_name() == "FREETIME1", "AC1: full-day run resumes from FREETIME1")
	var guard: int = 0
	while guard < 40:
		TimeManager.advance(0.25)
		guard += 1
		await get_tree().process_frame
		if TimeManager.get_state() == TimeManager.DayState.SAVE:
			break
	var expected: Array = [
		TimeManager.DayState.PERIOD1, TimeManager.DayState.FREETIME1,
		TimeManager.DayState.PERIOD2, TimeManager.DayState.FREETIME2,
		TimeManager.DayState.PERIOD3, TimeManager.DayState.FREETIME3,
		TimeManager.DayState.PERIOD4, TimeManager.DayState.DAYEND,
		TimeManager.DayState.SAVE,
	]
	var ordered: Array = []
	for state in _states:
		if ordered.is_empty() or ordered[ordered.size() - 1] != state:
			ordered.append(state)
	var sequence_ok: bool = true
	var cursor: int = 0
	for expected_state in expected:
		while cursor < ordered.size() and ordered[cursor] != expected_state:
			cursor += 1
		if cursor >= ordered.size():
			sequence_ok = false
			break
		cursor += 1
	_check(sequence_ok, "AC1: full day runs Period1 -> ... -> DayEnd -> Save in order")
	_check(
		SaveManager.has_slot(SaveManager.AUTOSAVE_SLOT),
		"AC1: DayEnd writes the autosave slot"
	)


## --- AC4: save at DayEnd and reload identically -----------------------------

func _check_save_reload() -> void:
	_before_reload = _capture_state()
	var written: bool = SaveManager.save_slot(INTEGRATION_SLOT, {}, true)
	_check(written, "AC4: named save slot written")
	if not written:
		return
	var saved: SaveGame = SaveManager.load_slot(INTEGRATION_SLOT)
	_check(saved != null, "AC4: saved resource loads and validates")
	if saved == null:
		return
	_check(saved.version == SaveGame.CURRENT_VERSION, "AC4: save version recorded")
	_check(
		saved.player_instance != null and not saved.player_instance.template_id.is_empty(),
		"AC4: player instance keeps stable template linkage"
	)

	var previous: Node = _game
	_check(GameManager.load_slot(INTEGRATION_SLOT), "AC4: GameManager loads the slot")
	_game = await _wait_for_game(previous)
	if _game == null:
		_check(false, "AC4: Game scene rebuilt after load")
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_wire_game_signals()
	var after: Dictionary = _capture_state()
	_check(
		_states_equal(_before_reload, after),
		"AC4: stats/mood/meters/positions/period restored identically (text-resource float precision)"
	)
	_check(_template_linkage_ok(), "AC4: NPC template linkage intact after reload")


## --- AC5 / AC6: mod discovery, invalid mods and disabling -------------------

func _check_mods() -> void:
	_create_synthetic_mods()
	ModLoader.load_mods(MODS_TEST_ROOT)

	var loaded: Array = ModLoader.get_loaded_mods()
	_check(loaded.has("integration_valid"), "AC5: valid mod discovered and loaded")
	_check(
		ModLoader.has_resource(ModLoader.TYPE_DIALOGUE, "topic:integration_valid"),
		"AC5: valid mod's resource registered"
	)

	var report: Array = ModLoader.get_last_report()
	# Discovery-stage skips are keyed by folder name, not the (invalid) manifest id.
	_check(_has_skip(report, "invalid"), "AC5: invalid manifest skipped with a report entry")
	_check(_has_skip(report, "integration_missingdep"), "AC5: missing-dependency mod skipped with a report entry")
	_check(
		not ModLoader.has_resource(ModLoader.TYPE_DIALOGUE, "topic:integration_disabled"),
		"AC6: disabled mod's resources excluded"
	)

	# File-based disable: a .disabled marker must exclude an otherwise valid mod.
	_write_text(MODS_TEST_ROOT + "valid/.disabled", "")
	ModLoader.load_mods(MODS_TEST_ROOT)
	_check(
		not ModLoader.has_resource(ModLoader.TYPE_DIALOGUE, "topic:integration_valid"),
		"AC6: .disabled marker excludes a mod's resources"
	)

	_remove_file(MODS_TEST_ROOT + "valid/.disabled")
	# Restore the real registries so later checks see the shipped base content.
	ModLoader.load_mods()


## --- AC7: missing template on load is recoverable ---------------------------

func _check_missing_template_recovery() -> void:
	var saved: SaveGame = SaveManager.load_slot(INTEGRATION_SLOT)
	if saved == null:
		_check(false, "AC7: missing-template save could not be prepared")
		return
	var modified: SaveGame = saved.duplicate(true) as SaveGame
	modified.slot_name = MISSING_TEMPLATE_SLOT
	modified.write_seq = saved.write_seq + 1
	var npcs: Array = modified.npc_instances
	if npcs.is_empty():
		_check(false, "AC7: save has no NPC instances to degrade")
		return
	var victim: NpcInstance = npcs[0] as NpcInstance
	victim.template_id = "char:does_not_exist"
	var err: int = ResourceSaver.save(modified, SaveManager.get_save_path(MISSING_TEMPLATE_SLOT))
	_check(err == OK, "AC7: synthetic missing-template save written")

	var previous: Node = _game
	_check(GameManager.load_slot(MISSING_TEMPLATE_SLOT), "AC7: load with a missing template does not crash")
	_game = await _wait_for_game(previous)
	if _game == null:
		_check(false, "AC7: Game scene survives a missing template")
		return
	var retained: bool = false
	var npcs_root: Node = _game.get_node_or_null("Npcs")
	if npcs_root != null:
		for npc_variant in npcs_root.get_children():
			var npc: Node = npc_variant as Node
			var instance: NpcInstance = npc.get("instance") as NpcInstance
			if instance != null and instance.template_id == "char:does_not_exist":
				retained = true
				break
	_check(retained, "AC7: instance with missing template restored verbatim")
	_check(TimeManager.is_running(), "AC7: day clock still running after recovery")


## --- Helpers ----------------------------------------------------------------

## Clear the slots this harness owns before the day starts. Without this, a
## stale autosave from an earlier run would make the DayEnd existence check pass
## even if autosave regressed. An existing autosave is backed up first.
func _prepare_save_fixture() -> void:
	var autosave_path: String = SaveManager.get_save_path(SaveManager.AUTOSAVE_SLOT)
	_had_autosave = FileAccess.file_exists(autosave_path)
	if _had_autosave:
		_autosave_backup = FileAccess.get_file_as_bytes(autosave_path)
	for slot in [SaveManager.AUTOSAVE_SLOT, INTEGRATION_SLOT, MISSING_TEMPLATE_SLOT]:
		if SaveManager.has_slot(slot):
			SaveManager.delete_slot(slot)


## Remove every artifact the harness wrote, restoring any pre-existing autosave.
func _restore_environment() -> void:
	for slot in [INTEGRATION_SLOT, MISSING_TEMPLATE_SLOT]:
		if SaveManager.has_slot(slot):
			SaveManager.delete_slot(slot)
	var autosave_path: String = SaveManager.get_save_path(SaveManager.AUTOSAVE_SLOT)
	if _had_autosave:
		var file: FileAccess = FileAccess.open(autosave_path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_autosave_backup)
			file.close()
	elif FileAccess.file_exists(autosave_path):
		SaveManager.delete_slot(SaveManager.AUTOSAVE_SLOT)
	_remove_dir_recursive(MODS_TEST_ROOT)


## Recursively delete a user:// directory tree. Godot 4.2 has no single-call
## recursive directory removal, so walk children depth-first.
func _remove_dir_recursive(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var child: String = path + entry
		if dir.current_is_dir():
			_remove_dir_recursive(child + "/")
		else:
			DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


## Record the live state in a comparable shape. Derived from the same instance
## data the save payload uses, so any drift after reload is visible.
func _capture_state() -> Dictionary:
	var player: NpcInstance = _game.get("_player_instance") as NpcInstance
	# Mirror Game._provide_save_state(): the player node is authoritative for its
	# world position, while the instance only carries it at save boundaries.
	var player_node: Node2D = _game.get_node_or_null("Player") as Node2D
	if player != null and player_node != null:
		player.position = player_node.global_position
	var npc_data: Dictionary = {}
	var npcs_root: Node = _game.get_node_or_null("Npcs")
	if npcs_root != null:
		for npc_variant in npcs_root.get_children():
			var npc: Node = npc_variant as Node
			var instance: NpcInstance = npc.get("instance") as NpcInstance
			if instance != null:
				npc_data[instance.instance_id] = instance.snapshot()
	return {
		"day": TimeManager.get_day_number(),
		"state": TimeManager.get_state(),
		# The full persisted day: phase elapsed, attendance, grades, roster and
		# the player id/absence flag -- not just the day number and state enum.
		"day_snapshot": TimeManager.get_day_snapshot(),
		"feedback": _game.get("show_relationship_feedback"),
		"player": player.snapshot() if player != null else {},
		"npcs": npc_data,
	}


## Compare restored state field by field. Godot text resources write floats with
## finite decimal precision, so Vector2 positions are compared with a 0.01 px
## tolerance; all other values (stats, meters, schedule, ids, enums) compare
## exactly. This is the "identically" of a round-trip through the save format.
func _states_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a.keys():
		if not b.has(key) or not _value_equal(a[key], b[key]):
			return false
	return true


func _value_equal(a: Variant, b: Variant) -> bool:
	if a is Vector2 and b is Vector2:
		return absf((a as Vector2).x - (b as Vector2).x) <= 0.01 \
			and absf((a as Vector2).y - (b as Vector2).y) <= 0.01
	if a is Dictionary and b is Dictionary:
		var left: Dictionary = a
		var right: Dictionary = b
		if left.size() != right.size():
			return false
		for key in left.keys():
			if not right.has(key) or not _value_equal(left[key], right[key]):
				return false
		return true
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in range((a as Array).size()):
			if not _value_equal((a as Array)[i], (b as Array)[i]):
				return false
		return true
	if a is float and b is float:
		# Text-resource serialization rounds floats; e.g. phase_elapsed 0.1 is
		# not bit-identical after a .tres round-trip.
		return absf((a as float) - (b as float)) <= 0.01
	return a == b


## Every restored NPC (and the player) must still resolve an authored template.
func _template_linkage_ok() -> bool:
	var player: NpcInstance = _game.get("_player_instance") as NpcInstance
	if player == null or player.resolve_template() == null:
		return false
	var npcs_root: Node = _game.get_node_or_null("Npcs")
	if npcs_root == null:
		return false
	for npc_variant in npcs_root.get_children():
		var npc: Node = npc_variant as Node
		var instance: NpcInstance = npc.get("instance") as NpcInstance
		if instance == null or instance.resolve_template() == null:
			return false
	return true


## A one-line accessor for the before/after party snapshots in a resolver result.
func _party_field(snapshot: Dictionary, party: String, field: String) -> int:
	var party_data: Dictionary = snapshot.get(party, {})
	return int(party_data.get(field, 0))


## Dispatch a real InputEventKey to a node's _unhandled_input handler. Headless
## Godot does not route parse_input_event() to those handlers, so this calls the
## exact handler the E key / number keys use in play.
func _send_key_to(node: Node, keycode: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	node.call("_unhandled_input", event)


## Wait for a Game scene root. `previous` excludes the old instance after a
## reload, so the runner cannot accidentally inspect the scene being freed.
func _wait_for_game(previous: Node = null) -> Node:
	for _i in range(600):
		await get_tree().process_frame
		var candidate: Node = get_tree().root.get_node_or_null("Game")
		if (
			candidate != null
			and candidate != previous
			and candidate.has_method("_provide_save_state")
		):
			return candidate
	return null


## --- Signal handlers --------------------------------------------------------

func _on_state_changed(new_state: int, _old_state: int) -> void:
	_states.append(new_state)


func _on_dialogue_resolved(result: Dictionary) -> void:
	_resolved.append(result)


func _on_npc_interaction_started(topic_id: String, initiator_id: String, target_id: String) -> void:
	_initiations.append([topic_id, initiator_id, target_id])


## --- AC10: documentation audit ----------------------------------------------

## Read every shipped GDScript and confirm it has a script-level doc header and
## that a majority of its functions carry a doc comment on the preceding line.
## Trivial accessors and `_ready()` stubs are not required to be documented; see
## the Ticket 018 ruling in doc/idea-v1-decisions.md. The harness is included.
func _verify_code_comments() -> bool:
	var dir: DirAccess = DirAccess.open("res://scripts/")
	if dir == null:
		return false
	var files: Array[String] = []
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.ends_with(".gd"):
			files.append("res://scripts/" + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	files.append("res://tests/IntegrationBootstrap.gd")
	files.append("res://tests/DayLoopIntegrationTest.gd")

	var total_funcs: int = 0
	var documented_funcs: int = 0
	for path in files:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			return false
		var text: String = file.get_as_text()
		file.close()
		# Several scripts put `class_name`/`extends` before their doc header;
		# accept a `##` header anywhere in the first few lines.
		var lines: PackedStringArray = text.split("\n")
		var header_ok: bool = false
		for i in range(mini(8, lines.size())):
			if lines[i].begins_with("##"):
				header_ok = true
				break
		if not header_ok:
			print("[018] undocumented script: " + path)
			return false
		for i in range(lines.size()):
			var stripped: String = lines[i].strip_edges()
			if not (stripped.begins_with("func ") or stripped.begins_with("static func ")):
				continue
			total_funcs += 1
			var previous: int = i - 1
			while previous >= 0 and lines[previous].strip_edges().is_empty():
				previous -= 1
			if previous >= 0 and lines[previous].strip_edges().begins_with("##"):
				documented_funcs += 1

	var coverage: float = float(documented_funcs) / float(maxi(1, total_funcs))
	print("[018] AC10 function doc coverage: %d/%d (%d%%)" % [
		documented_funcs, total_funcs, int(coverage * 100.0)
	])
	return coverage >= 0.5


## --- Synthetic mod tree -----------------------------------------------------

func _create_synthetic_mods() -> void:
	_write_text(
		MODS_TEST_ROOT + "valid/mod.json",
		'{"id":"integration_valid","name":"Integration Valid","version":"1.0.0",'
		+ '"author":"Verification","entry":"entry.gd","dependencies":[],"content":["topic.tres"]}'
	)
	_write_text(
		MODS_TEST_ROOT + "valid/entry.gd",
		"extends RefCounted\n## No-op entry point for the integration test's synthetic mod.\n"
		+ "func register(_loader) -> void:\n\tpass\n"
	)
	_write_text(MODS_TEST_ROOT + "valid/topic.tres", _topic_resource("topic:integration_valid"))

	# Missing the required `author` field -> skipped during discovery.
	_write_text(
		MODS_TEST_ROOT + "invalid/mod.json",
		'{"id":"integration_invalid","name":"Invalid","version":"1.0.0",'
		+ '"entry":"entry.gd","dependencies":[],"content":[]}'
	)
	_write_text(
		MODS_TEST_ROOT + "invalid/entry.gd",
		"extends RefCounted\n## Entry for the intentionally invalid mod.\nfunc register(_loader) -> void:\n\tpass\n"
	)

	# Declares a dependency that will never be loaded.
	_write_text(
		MODS_TEST_ROOT + "missingdep/mod.json",
		'{"id":"integration_missingdep","name":"Missing dep","version":"1.0.0",'
		+ '"author":"Verification","entry":"entry.gd",'
		+ '"dependencies":["integration_nonexistent"],"content":[]}'
	)
	_write_text(
		MODS_TEST_ROOT + "missingdep/entry.gd",
		"extends RefCounted\n## Entry for the missing-dependency mod.\nfunc register(_loader) -> void:\n\tpass\n"
	)

	# Valid manifest, but disabled via the flag -> resources must be excluded.
	_write_text(
		MODS_TEST_ROOT + "disabled/mod.json",
		'{"id":"integration_disabled","name":"Disabled","version":"1.0.0",'
		+ '"author":"Verification","entry":"entry.gd","enabled":false,"dependencies":[],'
		+ '"content":["topic.tres"]}'
	)
	_write_text(
		MODS_TEST_ROOT + "disabled/entry.gd",
		"extends RefCounted\n## Entry for the disabled mod.\nfunc register(_loader) -> void:\n\tpass\n"
	)
	_write_text(MODS_TEST_ROOT + "disabled/topic.tres", _topic_resource("topic:integration_disabled"))


## A minimal authored DialogueTopic .tres with a unique id so add-only rules
## cannot collide with the shipped sample mod.
func _topic_resource(topic_id: String) -> String:
	return (
		'[gd_resource type="Resource" script_class="DialogueTopic" load_steps=2 format=3]\n\n'
		+ '[ext_resource type="Script" path="res://scripts/DialogueTopic.gd" id="1_topic"]\n\n'
		+ '[resource]\nscript = ExtResource("1_topic")\n'
		+ 'id = "%s"\n' % topic_id
		+ 'text = "Integration topic"\n'
		+ 'min_mood = 0\nmin_familiarity = 0\nmin_affection = 0\n'
		+ 'required_interests = PackedStringArray()\nrequired_traits = PackedStringArray()\n'
		+ 'required_stat = ""\nrequired_stat_min = 0\n'
		+ 'checked_stat = "wisdom"\ndifficulty = 1\n'
		+ 'affection_delta_success = 1\nfamiliarity_delta_success = 1\nmood_delta_success = 1\n'
		+ 'affection_delta_failure = 0\nfamiliarity_delta_failure = 0\nmood_delta_failure = 0\n'
	)


func _write_text(path: String, text: String) -> void:
	var folder: String = path.substr(0, path.rfind("/"))
	DirAccess.make_dir_recursive_absolute(folder)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _has_skip(report: Array, mod_id: String) -> bool:
	for entry_variant in report:
		var entry: Dictionary = entry_variant
		if str(entry.get("mod", "")) == mod_id and str(entry.get("status", "")) == "skipped":
			return true
	return false


## --- Assertion / completion -------------------------------------------------

func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("[018] PASS " + label)
	else:
		_failed += 1
		print("[018] FAIL " + label)


func _finish() -> void:
	print("[018] RESULT passed=%d failed=%d" % [_passed, _failed])
	if _failed == 0:
		print("ALL_018_CHECKS_PASSED")
	else:
		print("SOME_018_CHECKS_FAILED")
	get_tree().quit(0 if _failed == 0 else 1)
