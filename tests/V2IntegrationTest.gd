## V2IntegrationTest
##
## Persistent headless acceptance harness for ticket 033. One runner exercises
## the whole v2 flow through real entry points: Main Menu/New Game, a
## player-initiated conversation (authored greeting, topic rolls, reactive line,
## two-pick limit, both parties' meters/mood, feedback), an NPC-initiated
## single-reply talk in free time, pause + named Save As + reload through the
## embedded Load Game screen, Options and Mods Menu operations, and a
## relationship-driven goal observed on a real Npc after the reload.
##
## Assertions are on external behavior only — visible labels/choices, emitted
## resolver payloads, meter/mood deltas, persisted slots/settings/mod flags and
## goal strings/destinations. Prints ALL_033_CHECKS_PASSED on a full pass.
extends Node

const EXPECTED_CHECKS: int = 63
const SLOT: String = "v2_integration"
const TEST_CONFIG_PATH: String = "user://v2_integration_settings.cfg"

var _passed: int = 0
var _failed: int = 0
var _game: Node = null
var _resolved: Array = []
var _original_config_path: String = ""
var _cleaned_up: bool = false


func _ready() -> void:
	call_deferred("_run")


## Last-resort cleanup: a fatal abort inside an awaited section must not leave the
## isolated settings file or the test save slot behind, or wedge the headless run.
func _exit_tree() -> void:
	_cleanup()


func _run() -> void:
	_isolate_settings()
	_remove_slot(SLOT)
	TimeManager.set_process(false)
	TimeManager.period_duration_sec = 45.0
	TimeManager.free_time_duration_sec = 30.0
	TimeManager.transition_duration_sec = 1.0

	await _check_menu_and_new_game()
	if _game == null:
		_finish()
		return

	await _check_player_conversation()
	await _check_npc_initiated_conversation()
	await _check_pause_save_and_reload()
	if _game == null:
		_finish()
		return

	await _check_options_from_pause()
	await _check_mods_from_pause()
	_check_relationship_goals()
	_check_registry_content()
	await _check_extra_coverage()

	_check(_passed == EXPECTED_CHECKS - 1, "T63: every planned 033 check executed")
	_finish()


## --- Setup -------------------------------------------------------------------

func _isolate_settings() -> void:
	_original_config_path = SettingsManager.get_config_path()
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CONFIG_PATH))
	SettingsManager.set_config_path(TEST_CONFIG_PATH)
	# The developer's real settings can have a mod flag already written (ticket
	# 018's harness writes one). Re-scan with the isolated store so the Mods Menu
	# rows and load snapshot reflect this ticket's fixture, not that flag.
	ModLoader.load_mods_from_roots(ModLoader.get_mods_roots())


## --- T1-T4: Main Menu / New Game ---------------------------------------------

func _check_menu_and_new_game() -> void:
	GameManager.show_main_menu()
	await _settle()
	var menu: Control = get_tree().current_scene as Control
	_check(menu != null and menu.name == "MainMenu", "T1: MainMenu is the configured entry point")
	if menu == null:
		return
	var expected: Array = [
		["NewGameButton", "New Game"],
		["LoadGameButton", "Load Game"],
		["OptionsButton", "Options"],
		["ModsButton", "Mods Menu"],
		["QuitButton", "Quit"],
	]
	var labels_ok: bool = true
	for entry in expected:
		var button := menu.get_node_or_null("CenterBox/%s" % entry[0]) as Button
		if button == null or button.text != str(entry[1]):
			labels_ok = false
	_check(labels_ok, "T2: all five Main Menu buttons exist with their labels")

	var new_game: Button = menu.get_node_or_null("CenterBox/NewGameButton") as Button
	if new_game != null:
		new_game.pressed.emit()
	_game = await _wait_for_game(null)
	_check(
		_game != null and TimeManager.get_day_number() == 1
		and TimeManager.get_state_name() == "PERIOD1",
		"T3: New Game starts the default debug day at day 1 / PERIOD1"
	)
	if _game == null:
		return
	_game.set("npc_initiation_enabled", false)
	_game.set("class_travel_lead_sec", 0.0)
	_game.set("show_relationship_feedback", true)
	_connect_game_signals(_game)
	var roster: Dictionary = _game.get("_instances_by_id") as Dictionary
	var npcs_root: Node = _game.get_node_or_null("Npcs")
	_check(
		roster.size() == 5 and npcs_root != null and npcs_root.get_child_count() == 4
		and _game.get("_player_instance") != null,
		"T4: player plus four NPCs spawn with a wired roster"
	)


## --- T5-T17: player-initiated conversation -----------------------------------

func _check_player_conversation() -> void:
	var ui: ConversationUI = _game.get_node_or_null("DialogueLayer/ConversationUI") as ConversationUI
	var player: Node2D = _game.get_node_or_null("Player") as Node2D
	var npcs_root: Node = _game.get_node_or_null("Npcs")
	var interaction: Node = _game.get_node_or_null("Player/InteractionComponent")
	if ui == null or player == null or npcs_root == null or interaction == null or npcs_root.get_child_count() == 0:
		_check(false, "T5: player conversation setup (missing scene nodes)")
		return
	var target: Npc = npcs_root.get_child(0) as Npc
	player.global_position = target.global_position + Vector2(12.0, 0.0)
	await _frames(4)
	_send_key(interaction, KEY_E)
	await _frames(3)
	_check(ui.is_open(), "T5: E at an NPC opens the conversation overlay")

	# AC5: initiation must not start a second talk while a conversation is open.
	var conversation_before: Variant = _game.get("_conversation")
	_game.set("npc_initiation_enabled", true)
	_game.set("npc_initiation_check_interval_sec", 0.05)
	_game.call("set_npc_initiation_gate", Callable(self, "_gate_true"))
	_game.call("_process", 2.1)
	await _frames(2)
	_check(ui.is_open() and _game.get("_conversation") == conversation_before,
		"T5b: the initiation loop cannot start a second talk while one is open")
	_game.call("set_npc_initiation_gate", Callable())
	_game.set("npc_initiation_enabled", false)

	var panel: PanelContainer = ui.get("_panel") as PanelContainer
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat if panel != null else null
	_check(
		panel != null and panel.anchor_bottom == 1.0 and panel.offset_top < 0.0
		and style != null and style.bg_color.a > 0.0 and style.bg_color.a < 1.0,
		"T6: a semi-transparent bottom overlay leaves the world visible"
	)

	var speaker_label: Label = ui.get("_speaker_label") as Label
	var speaking_id: String = str(_game.get("_conversation_npc_id"))
	var roster: Dictionary = _game.get("_instances_by_id") as Dictionary
	var speaking_instance: NpcInstance = roster.get(speaking_id) as NpcInstance
	_check(
		speaker_label != null and speaking_instance != null
		and speaker_label.text == speaking_instance.display_name,
		"T7: the overlay shows the speaking NPC's name"
	)

	var opening: Array = ui.call("get_choices") as Array
	var line_label: Label = ui.get("_line_label") as Label
	_check(
		line_label != null and not line_label.text.is_empty()
		and opening.size() == 1 and str(opening[0]).contains("Continue"),
		"T8: an authored greeting line is shown with one Continue"
	)
	_press_first_choice(ui)
	await _frames(2)
	var topics: Array = ui.call("get_choices") as Array
	_check(topics.size() >= 3 and topics.size() <= 5 and _buttons_numbered(ui),
		"T9: the greeting leads to a numbered 3-5 topic pool")

	var before: int = _resolved.size()
	_send_key(ui, KEY_1)
	await _frames(3)
	_check(_resolved.size() > before, "T10: a topic pick emits a resolver result")
	var result: Dictionary = _resolved[_resolved.size() - 1] if not _resolved.is_empty() else {}
	var deltas: Dictionary = result.get("deltas", {})
	_check(
		_has_nonzero_delta(deltas.get("initiator", {})) and _has_nonzero_delta(deltas.get("target", {})),
		"T11: both parties' meters/mood change after the first turn"
	)
	var feedback: Node = _game.get_node_or_null("FeedbackLayer/InteractionFeedbackUI")
	_check(feedback != null and bool(feedback.call("is_open")),
		"T12: meter feedback is shown after the turn")
	var after: Dictionary = result.get("after", {})
	var initiator_after: Dictionary = after.get("initiator", {})
	var target_after: Dictionary = after.get("target", {})
	_check(
		_relationship_consistent(initiator_after) and _relationship_consistent(target_after),
		"T13: both relationship types are re-derived from the updated meters"
	)
	var conversation: Conversation = _game.get("_conversation") as Conversation
	var reaction: Array = ui.call("get_choices") as Array
	var reaction_line: String = line_label.text if line_label != null else ""
	var response: Dictionary = conversation.get_last_response() if conversation != null else {}
	var layer: String = str(response.get("fallback", ""))
	# Under this fixture's fixed seed the exact layer is empty and the authored
	# topic-default layer wins. Requiring a non-exact layer makes the check fail if
	# fallback selection regresses to an unconditionally exact match.
	var reaction_ok: bool = (
		reaction.size() == 1 and str(reaction[0]).contains("Continue")
		and not reaction_line.is_empty() and not str(response.get("response_text", "")).is_empty()
		and layer in ["topic_default", "topic_partial", "generic_authored", "generated"]
	)
	if not reaction_ok:
		print("[033] DEBUG T14 reaction=%s line=%s layer=%s response=%s" % [reaction, reaction_line, layer, response])
	_check(reaction_ok,
		"T14: a non-empty reactive line is produced through the response fallback chain"
	)
	_check(conversation != null and conversation.get_turn() == 1,
		"T15: the greeting is not counted; the first pick is turn 1")

	_send_key(ui, KEY_1)
	await _frames(2)
	var followup: Array = ui.call("get_choices") as Array
	_check(followup.size() >= 3 and followup.size() <= 5,
		"T16: a second exchange offers a fresh 3-5 topic pool")
	if feedback != null:
		feedback.call("hide_feedback")
	_send_key(ui, KEY_1)
	await _frames(3)
	_check(feedback != null and bool(feedback.call("is_open")),
		"T17b: feedback is shown after the second turn as well")
	var final_choices: Array = ui.call("get_choices") as Array
	_check(
		final_choices.size() == 1 and str(final_choices[0]).contains("Leave")
		and conversation != null and conversation.get_turn() == 2
		and not conversation.can_pick_topic(),
		"T17: two picks is the hard limit and the last line offers only Leave"
	)
	ui.call("cancel_conversation")
	await _frames(2)
	_check(
		not ui.is_open() and not bool(player.call("is_input_locked"))
		and bool(interaction.call("is_enabled")),
		"T18: leaving releases input and interaction locks"
	)

	# The conversation owns Escape while it is open: the same event must end the
	# talk without opening pause behind it.
	_send_key(interaction, KEY_E)
	await _frames(3)
	if ui.is_open():
		var shared_escape := InputEventAction.new()
		shared_escape.action = "ui_cancel"
		shared_escape.pressed = true
		ui.call("_unhandled_input", shared_escape)
		_game.call("_unhandled_input", shared_escape)
		await _frames(2)
	var pause: Node = _game.get_node_or_null("PauseLayer/PauseMenu")
	_check(
		not ui.is_open() and pause != null and not bool(pause.call("is_open"))
		and not bool(_game.call("is_paused")),
		"T19: Escape while talking ends the talk and never opens pause"
	)


## --- T20-T27: free time + NPC-initiated single-reply talk --------------------

func _check_npc_initiated_conversation() -> void:
	var ui: ConversationUI = _game.get_node_or_null("DialogueLayer/ConversationUI") as ConversationUI
	var player: Node2D = _game.get_node_or_null("Player") as Node2D
	var npcs_root: Node = _game.get_node_or_null("Npcs")
	if ui == null or player == null or npcs_root == null or npcs_root.get_child_count() == 0:
		_check(false, "T20: NPC-initiated setup (missing scene nodes)")
		return

	# AC5: the default gate must refuse initiation during class time. Drive the
	# real Game._process() loop, not the inner helper it calls.
	_game.set("npc_initiation_enabled", true)
	_game.set("npc_initiation_check_interval_sec", 0.05)
	_game.call("set_npc_initiation_gate", Callable())
	_game.call("_process", 2.1)
	await _frames(2)
	_check(not ui.is_open() and not bool(_game.call("_npc_gate_open")),
		"T20b: the default gate refuses initiation during class time")
	_game.set("npc_initiation_enabled", false)

	TimeManager.advance(TimeManager.period_duration_sec + 1.0)
	await _frames(2)
	_check(
		TimeManager.get_state_name().begins_with("FREETIME")
		and TimeManager.is_free_time_state(TimeManager.get_state()),
		"T20: deterministic advance reaches free time"
	)

	# An injected false callable closes the real gate and the real loop honours it.
	# Arrange one eligible initiator so the check cannot pass for lack of a candidate.
	var candidate: Npc = null
	for child in npcs_root.get_children():
		var possible: Npc = child as Npc
		if (
			possible != null and possible.instance != null
			and NpcInitiation.can_initiate(
				possible.instance, possible.instance.resolve_template(), false, false
			)
		):
			candidate = possible
			break
	if candidate != null:
		candidate.clear_forced_destination()
		for child in npcs_root.get_children():
			var npc_candidate: Npc = child as Npc
			if npc_candidate != null:
				npc_candidate.set_conversation_busy(npc_candidate != candidate)
		(_game.get("_initiation_busy") as Dictionary).clear()
		(_game.get("_initiation_cooldowns") as Dictionary).clear()
		player.global_position = candidate.global_position + Vector2(8.0, 0.0)
	_game.set("npc_initiation_enabled", true)
	_game.call("set_npc_initiation_gate", Callable(self, "_gate_false"))
	var gate_closed: bool = not bool(_game.call("_npc_gate_open"))
	_game.call("_process", 2.1)
	await _frames(2)
	_check(gate_closed, "T21: an injected false callable closes the real gate")
	_check(not ui.is_open(), "T21b: the production initiation loop honours the false gate")
	_game.call("set_npc_initiation_gate", Callable())
	_game.set("npc_initiation_enabled", false)

	var initiator: Npc = npcs_root.get_child(0) as Npc
	for child in npcs_root.get_children():
		var npc: Npc = child as Npc
		if npc != null:
			npc.set_conversation_busy(npc != initiator)
	var busy: Dictionary = _game.get("_initiation_busy")
	busy.clear()
	var cooldowns: Dictionary = _game.get("_initiation_cooldowns")
	cooldowns.clear()
	player.global_position = initiator.global_position + Vector2(8.0, 0.0)
	await _frames(3)
	var feedback_ui: Node = _game.get_node_or_null("FeedbackLayer/InteractionFeedbackUI")
	if feedback_ui != null:
		feedback_ui.call("hide_feedback")
	var meters_before: Dictionary = _meter_snapshot(initiator)
	var loader: Node = NpcInstance._mod_loader()
	var topics: Array = []
	if loader != null:
		topics = loader.call("get_all", str(loader.get("TYPE_DIALOGUE"))) as Array
	var before: int = _resolved.size()
	_game.call("_try_one_initiation", initiator, initiator.instance.instance_id, topics, 4242)
	await _frames(3)
	var opening: Array = ui.call("get_choices") as Array
	var opening_label: Label = ui.get("_line_label") as Label
	_check(
		ui.is_open() and opening.size() == 1 and str(opening[0]).contains("Continue")
		and opening_label != null and not opening_label.text.is_empty(),
		"T22: an NPC-initiated talk opens with its own spoken topic"
	)
	_check(not _meters_changed(meters_before, _meter_snapshot(initiator)),
		"T23: the spoken opening applies no deltas")

	_send_key(ui, KEY_1)
	await _frames(2)
	var replies: Array = ui.call("get_choices") as Array
	_check(replies.size() >= 2 and replies.size() <= 3,
		"T24: the player gets a filtered 2-3 reply pool")
	var reply_line: String = str(replies[0]) if not replies.is_empty() else ""
	_send_key(ui, KEY_1)
	await _frames(3)
	_check(_resolved.size() > before, "T25: the player's reply resolves with a roll")
	_check(_meters_changed(meters_before, _meter_snapshot(initiator)),
		"T26: the reply applies the final meter/mood change")
	var initiator_line: Label = feedback_ui.get("_initiator_line") as Label if feedback_ui != null else null
	var target_line: Label = feedback_ui.get("_target_line") as Label if feedback_ui != null else null
	_check(
		initiator_line != null and target_line != null
		and initiator_line.text.begins_with("You:")
		and target_line.text.begins_with("%s:" % initiator.instance.display_name),
		"T27: feedback labels follow the reply roll direction (player is initiator)"
	)
	var line_label: Label = ui.get("_line_label") as Label
	_check(line_label != null and line_label.text == reply_line,
		"T28: the reply text becomes the player's spoken line")
	var final_choices: Array = ui.call("get_choices") as Array
	_check(final_choices.size() == 1, "T29: one reply ends the talk")
	ui.call("cancel_conversation")
	await _frames(2)
	_check(not ui.is_open() and not bool(player.call("is_input_locked")),
		"T30: the NPC-initiated talk releases input")


## --- T31-T35: pause, Save As, reload -----------------------------------------

func _check_pause_save_and_reload() -> void:
	var pause: Node = _game.get_node_or_null("PauseLayer/PauseMenu")
	if pause == null:
		_check(false, "T31: pause overlay setup")
		return
	_send_action(_game, "ui_cancel")
	await _frames(2)
	var elapsed_before: float = TimeManager.get_phase_elapsed()
	TimeManager.advance(5.0)
	_check(
		bool(_game.call("is_paused")) and bool(pause.call("is_open"))
		and TimeManager.is_paused()
		and is_equal_approx(TimeManager.get_phase_elapsed(), elapsed_before),
		"T31: Escape pauses the live day with no clock drift"
	)

	var input: LineEdit = pause.get_node_or_null("Box/MenuBox/SaveRow/SlotNameInput") as LineEdit
	var save_button: Button = pause.get_node_or_null("Box/MenuBox/SaveRow/SaveAsButton") as Button
	var status: Label = pause.get_node_or_null("Box/MenuBox/StatusLabel") as Label
	save_button.pressed.emit()
	input.text = SaveManager.MANUAL_SLOT
	save_button.pressed.emit()
	_check(
		status != null and status.text.contains("reserved")
		and not SaveManager.has_slot(SLOT),
		"T32: reserved slot names are rejected before any write"
	)
	input.text = SLOT
	save_button.pressed.emit()
	var saved: SaveGame = SaveManager.load_slot(SLOT)
	var saved_player: NpcInstance = saved.player_instance as NpcInstance if saved != null else null
	var live_day: Dictionary = TimeManager.get_day_snapshot()
	_check(
		saved != null and saved.slot_name == SLOT and saved_player != null
		and saved_player.template_id == "char:alex"
		and _values_equal(live_day, saved.day_snapshot),
		"T33: Save As writes full live state to a named slot with template linkage"
	)
	# The persisted payload is the contract: Game syncs the player's position from
	# its Node2D only inside the save state provider, so a live instance snapshot
	# taken before that point can still hold a stale position.
	var expected_state: Dictionary = _state_from_save(saved) if saved != null else {}

	var load_button: Button = pause.get_node_or_null("Box/MenuBox/LoadButton") as Button
	load_button.pressed.emit()
	await _frames(2)
	var embedded: Node = pause.get_node_or_null("PanelHost/LoadGame")
	var slot_list: VBoxContainer = embedded.get_node_or_null("CenterBox/SlotScroll/SlotList") as VBoxContainer if embedded != null else null
	var load_row: Node = null
	if slot_list != null:
		for i in range(slot_list.get_child_count()):
			var meta: Label = slot_list.get_child(i).get_node_or_null("MetaScroll/MetaLabel") as Label
			if meta != null and meta.text.begins_with(SLOT):
				load_row = slot_list.get_child(i)
				break
	_check(load_row != null, "T34: the named slot appears in the embedded Load Game list")
	if load_row == null:
		return
	var row_load: Button = load_row.get_node_or_null("LoadButton") as Button
	if row_load != null:
		row_load.pressed.emit()
	var previous: Node = _game
	_game = await _wait_for_game(previous)
	_check(_game != null, "T35: the Load Game row swaps back into Game.tscn")
	if _game == null:
		return
	_game.set("npc_initiation_enabled", false)
	_game.set("class_travel_lead_sec", 0.0)
	_connect_game_signals(_game)
	await _frames(2)
	var restored_state: Dictionary = _live_state(_game)
	var state_equal: bool = _values_equal(expected_state, restored_state)
	if not state_equal:
		print("[033] DEBUG state diff: %s" % _first_diff(expected_state, restored_state, "state"))
	_check(
		state_equal,
		"T36: reload restores day/stats/mood/meters/positions with template linkage"
	)
	_check(
		TimeManager.is_running() and not TimeManager.is_paused()
		and TimeManager.get_state_name().begins_with("FREETIME")
		and (TimeManager.get_day_number() == int(expected_state["day"].get("day", 0))),
		"T37: the restored day resumes in free time with a running clock"
	)


## --- T38-T41: Options from pause --------------------------------------------

func _check_options_from_pause() -> void:
	var pause: Node = _game.get_node_or_null("PauseLayer/PauseMenu")
	if pause == null:
		_check(false, "T38: Options pause setup")
		return
	_send_action(_game, "ui_cancel")
	await _frames(2)
	var options_button: Button = pause.get_node_or_null("Box/MenuBox/OptionsButton") as Button
	options_button.pressed.emit()
	await _frames(2)
	var options: Node = pause.get_node_or_null("PanelHost/Options")
	var expected_nodes: Array = [
		"SettingsScroll/SettingsBox/VolumeRow/VolumeSlider",
		"SettingsScroll/SettingsBox/CloseRadiusRow/CloseRadiusSpin",
		"SettingsScroll/SettingsBox/NearRadiusRow/NearRadiusSpin",
		"SettingsScroll/SettingsBox/CloseTickRow/CloseTickSpin",
		"SettingsScroll/SettingsBox/NearTickRow/NearTickSpin",
		"SettingsScroll/SettingsBox/FarTickRow/FarTickSpin",
		"SettingsScroll/SettingsBox/ResolutionRow/ResolutionOption",
		"SettingsScroll/SettingsBox/FullscreenRow/FullscreenCheck",
		"SettingsScroll/SettingsBox/LanguageRow/LanguageOption",
	]
	var structure_ok: bool = options != null
	for path in expected_nodes:
		if options == null or options.get_node_or_null(path) == null:
			structure_ok = false
	var language: OptionButton = options.get_node_or_null("SettingsScroll/SettingsBox/LanguageRow/LanguageOption") as OptionButton if options != null else null
	var feedback_toggle: Node = options.get_node_or_null("SettingsScroll/SettingsBox/FeedbackRow") if options != null else null
	_check(
		structure_ok and language != null and language.disabled
		and language.get_item_text(0) == "English" and feedback_toggle == null,
		"T38: Options shows volume/chunks/resolution/language, no feedback toggle"
	)

	var volume: HSlider = options.get_node_or_null("SettingsScroll/SettingsBox/VolumeRow/VolumeSlider") as HSlider
	if volume != null:
		volume.value = 40.0
		volume.drag_ended.emit(true)
	_check(
		is_equal_approx(SettingsManager.get_master_volume(), 0.4)
		and is_equal_approx(AudioManager.get_master_volume(), 0.4),
		"T39: a committed volume change applies immediately"
	)
	var close_radius: SpinBox = options.get_node_or_null("SettingsScroll/SettingsBox/CloseRadiusRow/CloseRadiusSpin") as SpinBox
	var near_radius: SpinBox = options.get_node_or_null("SettingsScroll/SettingsBox/NearRadiusRow/NearRadiusSpin") as SpinBox
	var close_tick: SpinBox = options.get_node_or_null("SettingsScroll/SettingsBox/CloseTickRow/CloseTickSpin") as SpinBox
	if close_radius != null and near_radius != null and close_tick != null:
		close_radius.value = 3.0
		near_radius.value = 6.0
		close_tick.value = 0.3
	var chunk: ChunkConfig = ChunkManager.get_config()
	_check(
		SettingsManager.get_close_radius_chunks() == 3
		and SettingsManager.get_near_radius_chunks() == 6
		and is_equal_approx(SettingsManager.get_close_tick_sec(), 0.3)
		and chunk.close_radius_chunks == 3
		and is_equal_approx(chunk.close_tick_sec, 0.3),
		"T40: chunk radius/rate edits apply immediately to the live simulation"
	)
	var resolution: OptionButton = options.get_node_or_null("SettingsScroll/SettingsBox/ResolutionRow/ResolutionOption") as OptionButton
	var fullscreen: CheckButton = options.get_node_or_null("SettingsScroll/SettingsBox/FullscreenRow/FullscreenCheck") as CheckButton
	if resolution != null:
		resolution.select(2)
		resolution.item_selected.emit(2)
	if fullscreen != null:
		fullscreen.button_pressed = true
	var notice: Node = options.get_node_or_null("RestartNotice")
	var notice_visible: bool = notice is CanvasItem and (notice as CanvasItem).visible
	_check(
		SettingsManager.get_resolution() == Vector2i(1920, 1080)
		and SettingsManager.get_fullscreen() and not notice_visible,
		"T41: resolution/fullscreen apply immediately with no misleading notice"
	)
	SettingsManager.reload()
	_check(
		is_equal_approx(SettingsManager.get_master_volume(), 0.4)
		and SettingsManager.get_close_radius_chunks() == 3
		and SettingsManager.get_resolution() == Vector2i(1920, 1080)
		and SettingsManager.get_fullscreen(),
		"T42: Options changes persist through a settings reload"
	)
	if fullscreen != null:
		fullscreen.button_pressed = false
	_embedded_back(options)
	await _frames(2)
	_check(str(pause.call("get_embedded_screen_name")) == "",
		"T43: Back from Options returns to pause without leaving the live day")


## --- T44-T46: Mods from pause ------------------------------------------------

func _check_mods_from_pause() -> void:
	var pause: Node = _game.get_node_or_null("PauseLayer/PauseMenu")
	var mods_button: Button = pause.get_node_or_null("Box/MenuBox/ModsButton") as Button
	mods_button.pressed.emit()
	await _frames(2)
	var mods: Node = pause.get_node_or_null("PanelHost/ModsMenu")
	var snapshot: Array = ModLoader.get_installed_mods()
	var row_index: int = -1
	var mod_id: String = ""
	for i in range(snapshot.size()):
		var entry: Dictionary = snapshot[i] as Dictionary
		if bool(entry.get("togglable", false)):
			row_index = i
			mod_id = str(entry.get("id", ""))
			break
	var row: Node = mods.get_node_or_null("ModScroll/ModBox/ModRow_%d" % row_index) if mods != null and row_index >= 0 else null
	var toggle: CheckButton = row.get_node_or_null("ToggleButton") as CheckButton if row != null else null
	_check(
		toggle != null and not toggle.disabled and not mod_id.is_empty(),
		"T44: the Mods Menu lists installed mods with an interactive toggle"
	)
	if toggle == null:
		return

	var loaded_before: Array = ModLoader.get_loaded_mods().duplicate()
	toggle.button_pressed = false
	var notice: Label = mods.get_node_or_null("RestartNotice") as Label
	_check(
		not SettingsManager.get_mod_enabled(mod_id)
		and bool(SettingsManager.get_mod_flags().get(mod_id, true)) == false
		and notice != null and notice.visible
		and notice.text.to_lower().contains("restart"),
		"T45: a toggle writes the flag, shows a restart notice, and does not rescan"
	)
	_check(ModLoader.get_loaded_mods() == loaded_before,
		"T46: the just-disabled mod still reads loaded until the next launch")
	SettingsManager.reload()
	_check(not SettingsManager.get_mod_enabled(mod_id),
		"T47: the mod disable flag persists through a settings reload")
	ModLoader.load_mods_from_roots(ModLoader.get_mods_roots())
	var after: Dictionary = _find_mod(ModLoader.get_installed_mods(), mod_id)
	_check(
		str(after.get("status", "")) == "skipped"
		and str(after.get("reason", "")).contains("disabled (settings flag)"),
		"T48: the flag takes effect on the next launch"
	)
	SettingsManager.clear_mod_flag(mod_id)
	_embedded_back(mods)
	await _frames(2)
	_check(str(pause.call("get_embedded_screen_name")) == "",
		"T49: Back from Mods returns to pause with the live day intact")
	_send_action(_game, "ui_cancel")
	await _frames(2)
	_check(not bool(_game.call("is_paused")),
		"T50: Escape resumes from pause after the menu operations")
	_check(
		not TimeManager.is_paused() and TimeManager.is_running(),
		"T51: the clock resumes without drift after Save As and menu operations"
	)


## --- T52-T54: relationship-driven goals after reload -------------------------

func _check_relationship_goals() -> void:
	var npcs_root: Node = _game.get_node_or_null("Npcs")
	var map: Map = _game.get_node_or_null("MapRenderer").get("map") as Map if _game.get_node_or_null("MapRenderer") != null else null
	if npcs_root == null or npcs_root.get_child_count() == 0 or map == null:
		_check(false, "T52: relationship goal setup")
		return
	var npc: Npc = npcs_root.get_child(0) as Npc
	var player: NpcInstance = _game.get("_player_instance") as NpcInstance
	if npc == null or npc.instance == null or player == null:
		_check(false, "T52: relationship goal setup")
		return
	var player_id: String = player.instance_id
	var roster: Array = (_game.get("_instances_by_id") as Dictionary).values()
	_set_meter(npc.instance, player_id, 70, 70)
	var seek_eval: int = _goal_eval_for(npc, map, roster, player_id, true)
	if seek_eval >= 0:
		npc.set("_eval_count", seek_eval)
		npc.call("evaluate_goal")
	var seek_ok: bool = (
		seek_eval >= 0 and str(npc.instance.current_goal) == "seek:%s" % player_id
		and npc.instance.goal_destination.distance_to(player.position) < 2.0
	)
	if not seek_ok:
		print("[033] DEBUG T52 seek_eval=%d seed=%s goal=%s dest=%s player=%s roster=%d hangouts=%s meter=%s" % [
			seek_eval, npc.get("_seed_value"), npc.instance.current_goal,
			npc.instance.goal_destination, player.position, roster.size(),
			map.get_hangout_marker_names(), npc.instance.get_meter(player_id),
		])
	_check(seek_ok,
		"T52: a friend/lover meter produces a pinned seek goal toward the player after reload"
	)

	# The implemented rule skips non-positive player weights instead of emitting
	# `avoid:player`; assert the chosen destination is not the enemy's position.
	_set_meter(npc.instance, player_id, 0, -70)
	var enemy_eval: int = _goal_eval_for(npc, map, roster, player_id, false)
	if enemy_eval >= 0:
		npc.set("_eval_count", enemy_eval)
		npc.call("evaluate_goal")
	_check(
		enemy_eval >= 0 and not str(npc.instance.current_goal).begins_with("seek:")
		and npc.instance.goal_destination.distance_to(player.position) >= 2.0,
		"T53: an enemy meter excludes the player destination and keeps a free-time goal"
	)

	# No roster re-wiring between these evaluations: a shared-reference change to
	# the restored meter must affect the very next goal the real Npc computes.
	_set_meter(npc.instance, player_id, 70, 70)
	npc.set("_eval_count", seek_eval)
	npc.call("evaluate_goal")
	_check(str(npc.instance.current_goal) == "seek:%s" % player_id,
		"T54: meter changes after restore affect the next goal without re-wiring")


## --- T55: authored content is registered -------------------------------------

func _check_registry_content() -> void:
	var loader: Node = NpcInstance._mod_loader()
	if loader == null:
		_check(false, "T55: content registry is available")
		return
	var traits: Array = loader.call("get_all", str(loader.get("TYPE_TRAIT"))) as Array
	var greetings: Array = loader.call("get_all", str(loader.get("TYPE_GREETING"))) as Array
	var topics: Array = loader.call("get_all", str(loader.get("TYPE_DIALOGUE"))) as Array
	var responses: Array = loader.call("get_all", str(loader.get("TYPE_RESPONSE"))) as Array
	var dialogue_total: int = greetings.size() + topics.size() + responses.size()
	_check(
		# 24 base traits (18 new + 6 v1) are approved in the decisions; the
		# spec's ~15-20 is the *new* trait count, not the registry total.
		traits.size() >= 20 and traits.size() <= 30
		and dialogue_total >= 40 and dialogue_total <= 60,
		"T55: authored traits and dialogue resources stay in the spec's ranges"
	)
	var trait_bucket: String = str(loader.get("TYPE_TRAIT"))
	var original_trait: Trait = traits[0] as Trait if not traits.is_empty() else null
	if original_trait != null:
		var duplicate: Trait = Trait.new()
		duplicate.id = original_trait.id
		var rejected: bool = not bool(loader.call("register_resource", trait_bucket, duplicate, "v2_integration_probe"))
		var original_kept: bool = loader.call("get_resource", trait_bucket, original_trait.id) == original_trait
		_check(rejected and original_kept,
			"T55b: duplicate trait id is rejected add-only")
	else:
		_check(false, "T55b: duplicate trait id is rejected add-only")


## --- T34b/T51b: remaining AC8 coverage ---------------------------------------

func _check_extra_coverage() -> void:
	var pause: Node = _game.get_node_or_null("PauseLayer/PauseMenu")
	if pause == null:
		_check(false, "T34b: the row's Delete button removes the named slot")
		_check(false, "T51b: F5/F9 debug hotkeys still save and load")
		return
	_send_action(_game, "ui_cancel")
	await _frames(2)
	var load_button: Button = pause.get_node_or_null("Box/MenuBox/LoadButton") as Button
	if load_button != null:
		load_button.pressed.emit()
		await _frames(2)
		var embedded: Node = pause.get_node_or_null("PanelHost/LoadGame")
		var row: Node = _find_slot_row(embedded, SLOT)
		var delete_button: Button = row.get_node_or_null("DeleteButton") as Button if row != null else null
		if delete_button != null:
			delete_button.pressed.emit()
			delete_button.pressed.emit()
		_check(not SaveManager.has_slot(SLOT),
			"T34b: the row's Delete button removes the named slot")
		_embedded_back(embedded)
		await _frames(2)
	else:
		_check(false, "T34b: the row's Delete button removes the named slot")
	_send_action(_game, "ui_cancel")
	await _frames(2)

	# Remove any pre-existing manual slot so F5 must actually create it.
	_remove_slot(SaveManager.MANUAL_SLOT)
	var swaps_before: int = GameManager.scene_change_count
	_send_action(_game, "manual_save")
	await _frames(2)
	var manual_saved: bool = SaveManager.has_slot(SaveManager.MANUAL_SLOT)
	_send_action(_game, "manual_load")
	await _frames(2)
	_check(manual_saved and GameManager.scene_change_count > swaps_before,
		"T51b: F5/F9 debug hotkeys still save and load")


## --- Helpers -----------------------------------------------------------------

func _isolate_settings_restore() -> void:
	if not _original_config_path.is_empty():
		SettingsManager.set_config_path(_original_config_path)
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CONFIG_PATH))


func _remove_slot(slot: String) -> void:
	if SaveManager.has_slot(slot):
		SaveManager.delete_slot(slot)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _connect_game_signals(game: Node) -> void:
	if game != null and not game.is_connected("dialogue_resolved", Callable(self, "_on_dialogue_resolved")):
		game.connect("dialogue_resolved", Callable(self, "_on_dialogue_resolved"))


func _wait_for_game(previous: Node) -> Node:
	for i in range(600):
		var scene: Node = get_tree().current_scene
		if (
			scene != null and scene.name == "Game" and scene != previous
			and scene.has_method("is_conversation_open")
		):
			await _frames(2)
			return scene
		await get_tree().process_frame
	return null


func _send_key(node: Node, keycode: int) -> void:
	if node == null:
		return
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	node.call("_unhandled_input", event)


func _send_action(node: Node, action: String) -> void:
	if node == null:
		return
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	node.call("_unhandled_input", event)


func _gate_false() -> bool:
	return false


func _press_first_choice(ui: ConversationUI) -> void:
	var box: Node = ui.get("_choices_box") as Node
	if box == null or box.get_child_count() == 0:
		return
	var button: Button = box.get_child(0) as Button
	if button != null:
		button.pressed.emit()


func _buttons_numbered(ui: ConversationUI) -> bool:
	var box: Node = ui.get("_choices_box") as Node
	if box == null or box.get_child_count() == 0:
		return false
	for i in range(box.get_child_count()):
		var button: Button = box.get_child(i) as Button
		if button == null or not button.text.begins_with("%d." % (i + 1)):
			return false
	return true


## Relationship type expected from the post-roll meter, using the resolver's
## thresholds. At >=60/>=60 the mutual-romance gate may yield Lover or Friend.
func _relationship_consistent(party: Dictionary) -> bool:
	var familiarity: int = int(party.get("familiarity", 0))
	var affection: int = int(party.get("affection", 0))
	var actual: String = str(party.get("relationship", ""))
	if familiarity >= DialogueResolver.REL_LOVER_FAM and affection >= DialogueResolver.REL_LOVER_AFF:
		return actual == DialogueResolver.TYPE_LOVER or actual == DialogueResolver.TYPE_FRIEND
	if affection <= DialogueResolver.REL_ENEMY_AFF:
		return actual == DialogueResolver.TYPE_ENEMY
	if familiarity >= DialogueResolver.REL_FRIEND_FAM and affection >= DialogueResolver.REL_FRIEND_AFF:
		return actual == DialogueResolver.TYPE_FRIEND
	if familiarity >= DialogueResolver.REL_FRIEND_FAM:
		return actual == DialogueResolver.TYPE_ACQUAINTANCE
	return actual == DialogueResolver.TYPE_STRANGER


func _has_nonzero_delta(delta: Dictionary) -> bool:
	for field in ["familiarity", "affection", "mood"]:
		if int(delta.get(field, 0)) != 0:
			return true
	return false


func _meter_snapshot(npc: Npc) -> Dictionary:
	var player_instance: NpcInstance = _game.get("_player_instance") as NpcInstance
	if player_instance == null or npc.instance == null:
		return {}
	var player_meter: Dictionary = player_instance.get_meter(npc.instance.instance_id).duplicate(true)
	var npc_meter: Dictionary = npc.instance.get_meter(player_instance.instance_id).duplicate(true)
	return {
		"p_fam": int(player_meter.get("familiarity", 0)),
		"p_aff": int(player_meter.get("affection", 0)),
		"n_fam": int(npc_meter.get("familiarity", 0)),
		"n_aff": int(npc_meter.get("affection", 0)),
		"p_mood": player_instance.mood,
		"n_mood": npc.instance.mood,
	}


func _meters_changed(before: Dictionary, after: Dictionary) -> bool:
	for key in before.keys():
		if int(before[key]) != int(after.get(key, 0)):
			return true
	return false


## Find one deterministic evaluation index for the expected goal shape so the
## harness asserts a pinned outcome instead of "any of N rolls".
func _goal_eval_for(npc: Npc, map: Map, roster: Array, player_id: String, want_seek: bool) -> int:
	var player_instance: NpcInstance = _game.get("_player_instance") as NpcInstance
	if player_instance == null:
		return -1
	var seed_value: int = int(npc.get("_seed_value"))
	var template: CharacterTemplate = npc.instance.resolve_template()
	for eval_count in range(30):
		var result: Dictionary = NpcAi.select_goal(
			npc.instance, template, map, seed_value, eval_count, roster, player_id
		)
		var goal: String = str(result.get("goal", ""))
		var destination_variant: Variant = result.get("destination", Vector2.ZERO)
		var destination: Vector2 = destination_variant if destination_variant is Vector2 else Vector2.ZERO
		var near_player: bool = destination.distance_to(player_instance.position) < 2.0
		if want_seek and goal == "seek:%s" % player_id and near_player:
			return eval_count
		if not want_seek and not goal.begins_with("seek:") and not near_player:
			return eval_count
	return -1


func _set_meter(instance: NpcInstance, other_id: String, familiarity: int, affection: int) -> void:
	var meter: Dictionary = instance.get_meter(other_id)
	meter["familiarity"] = familiarity
	meter["affection"] = affection


func _live_state(game: Node) -> Dictionary:
	var roster: Dictionary = game.get("_instances_by_id") as Dictionary
	var instances: Dictionary = {}
	for key in roster.keys():
		var instance: NpcInstance = roster[key] as NpcInstance
		if instance != null:
			instances[str(key)] = _progress_snapshot(instance)
	var player: NpcInstance = game.get("_player_instance") as NpcInstance
	return {
		"day": TimeManager.get_day_snapshot(),
		"player": _progress_snapshot(player) if player != null else {},
		"instances": instances,
	}


## The same comparable shape as _live_state(), read from a persisted slot.
func _state_from_save(save: SaveGame) -> Dictionary:
	var instances: Dictionary = {}
	for variant in save.npc_instances:
		var instance: NpcInstance = variant as NpcInstance
		if instance != null:
			instances[instance.instance_id] = _progress_snapshot(instance)
	var player: NpcInstance = save.player_instance as NpcInstance
	if player != null:
		instances[player.instance_id] = _progress_snapshot(player)
	return {
		"day": save.day_snapshot,
		"player": _progress_snapshot(player) if player != null else {},
		"instances": instances,
	}


func _progress_snapshot(instance: NpcInstance) -> Dictionary:
	var data: Dictionary = instance.snapshot()
	# Free-time AI goals are runtime state re-evaluated on load, not progress.
	data.erase("current_goal")
	data.erase("goal_destination")
	return data


func _values_equal(a: Variant, b: Variant) -> bool:
	if a is float and b is float:
		return is_equal_approx(float(a), float(b))
	if a is Vector2 and b is Vector2:
		return (a as Vector2).distance_to(b as Vector2) < 2.0
	if a is Dictionary and b is Dictionary:
		var left: Dictionary = a as Dictionary
		var right: Dictionary = b as Dictionary
		if left.size() != right.size():
			return false
		for key in left.keys():
			if not right.has(key) or not _values_equal(left[key], right[key]):
				return false
		return true
	if a is Array and b is Array:
		var left_array: Array = a as Array
		var right_array: Array = b as Array
		if left_array.size() != right_array.size():
			return false
		for i in range(left_array.size()):
			if not _values_equal(left_array[i], right_array[i]):
				return false
		return true
	return a == b


## Diagnostic only: first path whose values differ, for a failed state comparison.
func _first_diff(a: Variant, b: Variant, path: String) -> String:
	if a is float and b is float:
		if not is_equal_approx(float(a), float(b)):
			return "%s: %s != %s" % [path, a, b]
		return ""
	if a is Vector2 and b is Vector2:
		if (a as Vector2).distance_to(b as Vector2) >= 2.0:
			return "%s: %s != %s" % [path, a, b]
		return ""
	if a is Dictionary and b is Dictionary:
		var left: Dictionary = a as Dictionary
		var right: Dictionary = b as Dictionary
		if left.size() != right.size():
			return "%s: key count %d != %d (%s vs %s)" % [path, left.size(), right.size(), left.keys(), right.keys()]
		for key in left.keys():
			if not right.has(key):
				return "%s: missing key %s" % [path, key]
			var diff: String = _first_diff(left[key], right[key], "%s/%s" % [path, key])
			if not diff.is_empty():
				return diff
		return ""
	if a is Array and b is Array:
		var left_array: Array = a as Array
		var right_array: Array = b as Array
		if left_array.size() != right_array.size():
			return "%s: size %d != %d" % [path, left_array.size(), right_array.size()]
		for i in range(left_array.size()):
			var diff: String = _first_diff(left_array[i], right_array[i], "%s[%d]" % [path, i])
			if not diff.is_empty():
				return diff
		return ""
	if a != b:
		return "%s: %s != %s" % [path, a, b]
	return ""


func _find_slot_row(embedded: Node, slot: String) -> Node:
	var slot_list: VBoxContainer = embedded.get_node_or_null("CenterBox/SlotScroll/SlotList") as VBoxContainer if embedded != null else null
	if slot_list == null:
		return null
	for i in range(slot_list.get_child_count()):
		var meta: Label = slot_list.get_child(i).get_node_or_null("MetaScroll/MetaLabel") as Label
		if meta != null and meta.text.begins_with(slot):
			return slot_list.get_child(i)
	return null


func _find_mod(snapshot: Array, id: String) -> Dictionary:
	for entry_variant in snapshot:
		var entry: Dictionary = entry_variant as Dictionary
		if str(entry.get("id", "")) == id:
			return entry
	return {}


func _embedded_back(embedded: Node) -> void:
	if embedded == null:
		return
	var back: Button = embedded.get_node_or_null("BackButton") as Button
	if back == null:
		back = embedded.get_node_or_null("CenterBox/BackButton") as Button
	if back != null:
		back.pressed.emit()


func _on_dialogue_resolved(result: Dictionary) -> void:
	_resolved.append(result)


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("[033] PASS " + label)
	else:
		_failed += 1
		print("[033] FAIL " + label)


func _finish() -> void:
	_cleanup()
	print("[033] RESULT passed=%d failed=%d" % [_passed, _failed])
	if _failed == 0 and _passed == EXPECTED_CHECKS:
		print("ALL_033_CHECKS_PASSED")
	else:
		print("SOME_033_CHECKS_FAILED")
	get_tree().quit(0)


func _cleanup() -> void:
	if _cleaned_up:
		return
	_cleaned_up = true
	TimeManager.set_paused(false)
	TimeManager.set_process(true)
	_remove_slot(SLOT)
	_isolate_settings_restore()


func _gate_true() -> bool:
	return true
