## ConversationUITest
##
## Persistent headless acceptance harness for ticket 024. It drives the real
## `Game.tscn` scene and `ConversationUI` overlay through both conversation
## shapes, checks the overlay layout and portrait placeholders, verifies the
## input lock and the callable free-time gate, and re-uses the v1 signal seam
## (`dialogue_resolved` / `npc_interaction_started`) for observable assertions.
## Prints ALL_024_CHECKS_PASSED only when every assertion passed.
extends Node


const EXPECTED_CHECKS: int = 39

var _passed: int = 0
var _failed: int = 0
var _game: Node = null
var _resolved: Array = []
var _initiations: Array = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(_global_class_registered(), "T1: ConversationUI is a registered global class")

	TimeManager.set_process(false)
	TimeManager.period_duration_sec = 0.4
	TimeManager.free_time_duration_sec = 0.4
	TimeManager.transition_duration_sec = 0.2

	var packed := load("res://scenes/Game.tscn") as PackedScene
	if packed == null:
		_check(false, "T2: Game.tscn loads")
		_finish()
		return
	_game = packed.instantiate()
	get_tree().root.add_child(_game)
	await _frames(3)
	_game.set("npc_initiation_enabled", false)
	_game.set("show_relationship_feedback", true)
	# Keep NPCs out of class travel so initiation is not blocked by a forced walk.
	_game.set("class_travel_lead_sec", 0.0)
	if not _game.is_connected("dialogue_resolved", Callable(self, "_on_dialogue_resolved")):
		_game.connect("dialogue_resolved", Callable(self, "_on_dialogue_resolved"))
	if not _game.is_connected("npc_interaction_started", Callable(self, "_on_npc_interaction_started")):
		_game.connect("npc_interaction_started", Callable(self, "_on_npc_interaction_started"))
	_check(true, "T2: Game.tscn instantiates with the conversation overlay")

	_check_overlay_structure()
	await _check_player_flow()
	await _check_gate_callable()
	await _check_npc_initiated_flow()
	await _check_no_candidate_safety()
	_check(_passed == EXPECTED_CHECKS - 1, "T39: all expected 024 checks executed")
	_finish()


## --- T1-T5: overlay structure ------------------------------------------------

func _global_class_registered() -> bool:
	for entry in ProjectSettings.get_global_class_list():
		if str((entry as Dictionary).get("class", "")) == "ConversationUI":
			return true
	return false


func _check_overlay_structure() -> void:
	var ui: ConversationUI = _game.get_node_or_null("DialogueLayer/ConversationUI") as ConversationUI
	_check(ui != null, "T3: ConversationUI node exists under DialogueLayer")
	if ui == null:
		return
	var panel: PanelContainer = ui.get("_panel") as PanelContainer
	_check(
		panel != null and panel.anchor_bottom == 1.0 and panel.anchor_top == 1.0
		and panel.offset_top < 0.0,
		"T4: panel is anchored to the bottom of the screen"
	)
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat if panel != null else null
	_check(
		style != null and style.bg_color.a > 0.0 and style.bg_color.a < 1.0,
		"T5: panel background is semi-transparent (world stays visible)"
	)
	var left: Node = ui.get("_speaker_portrait") as Node
	var right: Node = ui.get("_listener_portrait") as Node
	var art_free: bool = left != null and right != null
	for slot in [left, right]:
		if slot == null:
			continue
		for child in (slot as Node).get_children():
			if child is TextureRect or child is Sprite2D:
				art_free = false
	_check(art_free, "T6: two transparent portrait slots exist and render no art")


## --- T6-T17: player-initiated flow -------------------------------------------

func _check_player_flow() -> void:
	var ui: ConversationUI = _game.get_node_or_null("DialogueLayer/ConversationUI") as ConversationUI
	var player: Node2D = _game.get_node_or_null("Player") as Node2D
	var npcs_root: Node = _game.get_node_or_null("Npcs")
	if ui == null or player == null or npcs_root == null or npcs_root.get_child_count() == 0:
		_check(false, "T7: player conversation setup (missing scene nodes)")
		return
	_check(true, "T7: player conversation setup is available")
	var target: Npc = npcs_root.get_child(0) as Npc
	var interaction: Node = _game.get_node_or_null("Player/InteractionComponent")
	player.global_position = target.global_position + Vector2(12.0, 0.0)
	await _frames(4)

	_send_key_to(interaction, KEY_E)
	await _frames(3)
	_check(ui.is_open(), "T8: E opens the conversation overlay")
	_check(bool(player.call("is_input_locked")), "T9: player input is locked")
	_check(not bool(interaction.call("is_enabled")), "T10: interaction component is disabled")

	var opening: Array = ui.call("get_choices") as Array
	_check(
		opening.size() == 1 and str(opening[0]).contains("Continue"),
		"T11: NPC greeting is shown with one Continue choice"
	)
	var speaker_label: Label = ui.get("_speaker_label") as Label
	var conversation_npc_id: String = str(_game.get("_conversation_npc_id"))
	var roster: Dictionary = _game.get("_instances_by_id") as Dictionary
	var speaking_instance: NpcInstance = roster.get(conversation_npc_id) as NpcInstance
	_check(
		speaker_label != null and speaking_instance != null
		and speaker_label.text == speaking_instance.display_name,
		"T12: the speaker name is shown"
	)

	# Use the Button.pressed path once, since headless Godot does not route
	# parse_input_event() to _unhandled_input (see the v1 harness note).
	_press_first_choice(ui)
	await _frames(2)
	var topics: Array = ui.call("get_choices") as Array
	_check(topics.size() >= 3 and topics.size() <= 5, "T13: greeting's first choice button opens a 3-5 topic pool")

	var resolved_before: int = _resolved.size()
	_send_key_to(ui, KEY_1)
	await _frames(3)
	_check(_resolved.size() > resolved_before, "T14: topic pick emits dialogue_resolved")
	var result: Dictionary = _resolved[_resolved.size() - 1] if not _resolved.is_empty() else {}
	var deltas: Dictionary = result.get("deltas", {})
	var initiator_delta: Dictionary = deltas.get("initiator", {})
	var target_delta: Dictionary = deltas.get("target", {})
	_check(
		_has_nonzero_delta(initiator_delta) and _has_nonzero_delta(target_delta),
		"T15: both parties receive at least one non-zero delta after the turn"
	)
	var feedback: Node = _game.get_node_or_null("FeedbackLayer/InteractionFeedbackUI")
	_check(feedback != null and bool(feedback.call("is_open")), "T16: feedback panel shows the turn")
	var reaction: Array = ui.call("get_choices") as Array
	_check(
		reaction.size() == 1 and str(reaction[0]).contains("Continue"),
		"T17: NPC reactive line is shown (not an immediate close)"
	)
	var conversation: Conversation = _game.get("_conversation") as Conversation
	_check(conversation != null and conversation.get_turn() == 1, "T18: first player pick counted once")

	_send_key_to(ui, KEY_1)
	await _frames(2)
	var followup: Array = ui.call("get_choices") as Array
	_check(followup.size() >= 3 and followup.size() <= 5, "T19: second exchange offers a new topic pool")

	_send_key_to(ui, KEY_1)
	await _frames(3)
	var final_choices: Array = ui.call("get_choices") as Array
	_check(
		final_choices.size() == 1 and str(final_choices[0]).contains("Leave"),
		"T20: second response ends with Leave only"
	)
	_check(conversation != null and conversation.get_turn() == 2, "T21: at most two player picks are allowed")

	ui.call("cancel_conversation")
	await _frames(2)
	_check(
		not ui.is_open() and not bool(player.call("is_input_locked"))
		and bool(interaction.call("is_enabled")),
		"T22: leaving releases input and interaction locks"
	)


## --- T18-T19: callable free-time gate ----------------------------------------

func _check_gate_callable() -> void:
	var ui: ConversationUI = _game.get_node_or_null("DialogueLayer/ConversationUI") as ConversationUI
	_game.set("npc_initiation_enabled", true)
	_game.set("npc_initiation_check_interval_sec", 0.05)
	_game.set("npc_initiation_hold_sec", 0.05)
	_game.set("npc_initiation_cooldown_sec", 0.05)
	_initiations.clear()
	_game.call("set_npc_initiation_gate", Callable(self, "_gate_false"))
	await _frames(15)
	_check(_initiations.is_empty(), "T23: a false gate blocks initiation")

	# Arrange a single eligible initiator and the player as its only target so the
	# production _process/gate path reaches the overlay, not a direct private call.
	var npcs_root: Node = _game.get_node_or_null("Npcs")
	var player: Node2D = _game.get_node_or_null("Player") as Node2D
	var candidate: Npc = null
	if npcs_root != null:
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
			var npc: Npc = child as Npc
			if npc != null:
				npc.set_conversation_busy(npc != candidate)
		var busy: Dictionary = _game.get("_initiation_busy")
		busy.clear()
		var cooldowns: Dictionary = _game.get("_initiation_cooldowns")
		cooldowns.clear()
		if player != null:
			player.global_position = candidate.global_position + Vector2(8.0, 0.0)
	_game.call("set_npc_initiation_gate", Callable(self, "_gate_true"))
	var start_ms: int = Time.get_ticks_msec()
	var frames: int = 0
	while _initiations.is_empty() and frames < 600 and Time.get_ticks_msec() - start_ms < 5000:
		await get_tree().process_frame
		frames += 1
	_check(not _initiations.is_empty(), "T24: an injected true gate fires outside free time")
	var gate_ui_open: bool = ui != null and ui.is_open()
	var gate_replies_ok: bool = false
	if gate_ui_open:
		var gate_opening: Array = ui.call("get_choices") as Array
		if gate_opening.size() == 1:
			_send_key_to(ui, KEY_1)
			await _frames(2)
		var gate_replies: Array = ui.call("get_choices") as Array
		gate_replies_ok = gate_replies.size() >= 2 and gate_replies.size() <= 3
	_check(
		gate_ui_open and gate_replies_ok,
		"T24b: the production gate path reaches the 2-3 reply UI"
	)
	if gate_ui_open:
		ui.call("cancel_conversation")
		await _frames(2)
	_game.call("set_npc_initiation_gate", Callable())
	_game.set("npc_initiation_enabled", false)


func _gate_false() -> bool:
	return false


func _gate_true() -> bool:
	return true


## --- T20-T28: NPC-initiated flow ---------------------------------------------

func _check_npc_initiated_flow() -> void:
	var ui: ConversationUI = _game.get_node_or_null("DialogueLayer/ConversationUI") as ConversationUI
	var player: Node2D = _game.get_node_or_null("Player") as Node2D
	var npcs_root: Node = _game.get_node_or_null("Npcs")
	if ui == null or player == null or npcs_root == null or npcs_root.get_child_count() == 0:
		_check(false, "T25: NPC-initiated setup (missing scene nodes)")
		return
	_check(true, "T25: NPC-initiated setup is available")
	# Clear any queued result from the player path so the feedback labels checked
	# below come from the reply roll, not an earlier panel.
	var feedback_ui: Node = _game.get_node_or_null("FeedbackLayer/InteractionFeedbackUI")
	if feedback_ui != null:
		feedback_ui.call("hide_feedback")
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
	var meters_before: Dictionary = _snapshot_meters(initiator)

	var loader: Node = NpcInstance._mod_loader()
	var topics: Array = []
	if loader != null:
		topics = loader.call("get_all", str(loader.get("TYPE_DIALOGUE"))) as Array
	var resolved_before: int = _resolved.size()
	_game.call("_try_one_initiation", initiator, initiator.instance.instance_id, topics, 4242)
	await _frames(3)

	_check(ui.is_open(), "T26: NPC→player initiation opens the overlay")
	var opening: Array = ui.call("get_choices") as Array
	_check(
		opening.size() == 1 and str(opening[0]).contains("Continue"),
		"T27: the NPC speaks its own opening topic"
	)
	_check(not _meters_changed(meters_before, _snapshot_meters(initiator)), "T28: opening applies no deltas")

	_send_key_to(ui, KEY_1)
	await _frames(2)
	var replies: Array = ui.call("get_choices") as Array
	_check(replies.size() >= 2 and replies.size() <= 3, "T29: player gets 2-3 filtered replies")
	var reply_text: String = str(replies[0]) if not replies.is_empty() else ""
	_send_key_to(ui, KEY_1)
	await _frames(3)
	_check(_resolved.size() > resolved_before, "T30: the reply resolves with a roll")
	_check(_meters_changed(meters_before, _snapshot_meters(initiator)), "T31: reply applies the final deltas")
	# The resolver's initiator is the player for this roll even though the
	# Conversation session records the NPC as its initiator.
	var initiator_line: Label = feedback_ui.get("_initiator_line") as Label if feedback_ui != null else null
	var target_line: Label = feedback_ui.get("_target_line") as Label if feedback_ui != null else null
	_check(
		initiator_line != null and target_line != null
		and initiator_line.text.begins_with("You:")
		and target_line.text.begins_with("%s:" % initiator.instance.display_name),
		"T37: feedback labels follow the roll direction, not the session ids"
	)
	var line_label: Label = ui.get("_line_label") as Label
	_check(
		line_label != null and line_label.text == reply_text,
		"T32: reply text becomes the player's spoken line"
	)
	var final_choices: Array = ui.call("get_choices") as Array
	_check(final_choices.size() == 1, "T33: one reply then the talk ends")

	ui.call("cancel_conversation")
	await _frames(2)
	_check(not ui.is_open() and not bool(player.call("is_input_locked")), "T34: NPC-initiated talk releases input")

	# Force an opening topic with no authored replies. The Game wiring must still
	# pick a reply-supported topic so the 2-3 option contract holds in real play.
	for child in npcs_root.get_children():
		var npc: Npc = child as Npc
		if npc != null:
			npc.set_conversation_busy(npc != initiator)
	busy.clear()
	cooldowns.clear()
	player.global_position = initiator.global_position + Vector2(8.0, 0.0)
	await _frames(2)
	var unauthored: Array = []
	var unauthored_topic: DialogueTopic = load("res://resources/dialogue/topic_ask_art.tres") as DialogueTopic
	if unauthored_topic != null:
		unauthored.append(unauthored_topic)
	_game.call("_try_one_initiation", initiator, initiator.instance.instance_id, unauthored, 9999)
	await _frames(3)
	var forced_opening: Array = ui.call("get_choices") as Array
	if forced_opening.size() == 1:
		_send_key_to(ui, KEY_1)
		await _frames(2)
	var forced_replies: Array = ui.call("get_choices") as Array
	_check(
		forced_replies.size() >= 2 and forced_replies.size() <= 3,
		"T38: unsupported opening topics are replaced by reply-supported ones"
	)
	if ui.is_open():
		ui.call("cancel_conversation")
		await _frames(2)


func _check_no_candidate_safety() -> void:
	var ui: ConversationUI = _game.get_node_or_null("DialogueLayer/ConversationUI") as ConversationUI
	var npcs_root: Node = _game.get_node_or_null("Npcs")
	if npcs_root == null or ui == null:
		return
	for child in npcs_root.get_children():
		var npc: Npc = child as Npc
		if npc != null:
			npc.set_conversation_busy(true)
	var busy: Dictionary = _game.get("_initiation_busy")
	busy.clear()
	_initiations.clear()
	_game.call("_try_npc_initiations")
	await _frames(2)
	_check(_initiations.is_empty() and not ui.is_open(), "T35: no candidates is a safe no-op")


## --- Helpers -----------------------------------------------------------------

func _snapshot_meters(initiator: Npc) -> Dictionary:
	var player_instance: NpcInstance = _game.get("_player_instance") as NpcInstance
	var npc_instance: NpcInstance = initiator.instance
	var player_meter: Dictionary = player_instance.get_meter(npc_instance.instance_id).duplicate(true)
	var npc_meter: Dictionary = npc_instance.get_meter(player_instance.instance_id).duplicate(true)
	return {
		"p_fam": int(player_meter.get("familiarity", 0)),
		"p_aff": int(player_meter.get("affection", 0)),
		"n_fam": int(npc_meter.get("familiarity", 0)),
		"n_aff": int(npc_meter.get("affection", 0)),
		"p_mood": player_instance.mood,
		"n_mood": npc_instance.mood,
	}


func _meters_changed(before: Dictionary, after: Dictionary) -> bool:
	for key in before.keys():
		if int(before[key]) != int(after.get(key, 0)):
			return true
	return false


func _has_nonzero_delta(delta: Dictionary) -> bool:
	for field in ["familiarity", "affection", "mood"]:
		if int(delta.get(field, 0)) != 0:
			return true
	return false


## Exercise the mouse/button path without relying on headless Input propagation.
func _press_first_choice(ui: ConversationUI) -> void:
	var box: Node = ui.get("_choices_box") as Node
	if box == null or box.get_child_count() == 0:
		return
	var button: Button = box.get_child(0) as Button
	if button != null:
		button.pressed.emit()


func _send_key_to(node: Node, keycode: int) -> void:
	if node == null:
		return
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	node.call("_unhandled_input", event)


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _on_dialogue_resolved(result: Dictionary) -> void:
	_resolved.append(result)


func _on_npc_interaction_started(topic_id: String, initiator_id: String, target_id: String) -> void:
	_initiations.append([topic_id, initiator_id, target_id])


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("[024] PASS %s" % label)
	else:
		_failed += 1
		print("[024] FAIL %s" % label)


func _finish() -> void:
	print("[024] RESULT passed=%d failed=%d" % [_passed, _failed])
	if _failed == 0 and _passed == EXPECTED_CHECKS:
		print("ALL_024_CHECKS_PASSED")
	else:
		print("SOME_024_CHECKS_FAILED")
	get_tree().quit(0)
