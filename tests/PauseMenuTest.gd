## PauseMenuTest
##
## Persistent headless acceptance harness for ticket 028. Boots the real
## Game.tscn, drives Escape through Game._unhandled_input, and asserts external
## behavior only: pause toggle, conversation-owned Escape, frozen/resumed clock
## with no drift, input/NPC freezes, named Save As from live state, Load route,
## embedded Options/Mods panels with a Back route to pause, and non-overlap of
## the pause and conversation overlays. Prints ALL_028_CHECKS_PASSED on a full pass.
extends Node

const EXPECTED_CHECKS: int = 40
const SLOT: String = "pause_ui_alpha"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _settle()
	_remove_slot(SLOT)
	# Deterministic clock: only the harness calls advance(), so a frozen clock
	# cannot be accidentally moved by the scene tree between assertions.
	TimeManager.set_process(false)

	# --- Boot the real playable day -------------------------------------------
	GameManager.start_fresh_day()
	await _settle()
	var game: Node = get_tree().current_scene
	_check(game != null and game.name == "Game", "T1: a fresh day boots into Game.tscn")
	if game == null:
		_finish()
		return
	game.set("npc_initiation_enabled", false)
	game.set("class_travel_lead_sec", 0.0)

	var pause: Node = game.get_node_or_null("PauseLayer/PauseMenu")
	_check(pause != null and pause.has_method("handle_cancel") and pause.has_method("open"),
		"T2: PauseMenu exists under PauseLayer with the expected seam")
	_check(pause != null and not bool(pause.call("is_open")), "T3: pause overlay starts hidden")
	_check(game.has_method("is_conversation_open") and not bool(game.call("is_conversation_open")),
		"T4: the conversation-ownership seam is exposed and initially false")
	if pause == null:
		_finish()
		return

	# --- Escape opens the pause and freezes the whole live scene ---------------
	_send_action(game, "ui_cancel")
	await _frames(2)
	_check(bool(game.call("is_paused")) and bool(pause.call("is_open")),
		"T5: Escape opens the pause overlay when no conversation is open")
	_check(TimeManager.is_paused(), "T6: TimeManager reports the clock paused")

	var elapsed_before: float = TimeManager.get_phase_elapsed()
	var day_before: int = TimeManager.get_day_number()
	var state_before: int = TimeManager.get_state()
	TimeManager.advance(5.0)
	_check(is_equal_approx(TimeManager.get_phase_elapsed(), elapsed_before),
		"T7: the day clock does not advance while paused")
	_check(TimeManager.get_day_number() == day_before and TimeManager.get_state() == state_before,
		"T8: day number and state stay intact while paused")

	var player: Node2D = game.get_node_or_null("Player") as Node2D
	var interaction: Node = game.get_node_or_null("Player/InteractionComponent")
	_check(player != null and bool(player.call("is_input_locked")),
		"T9: player input is locked while paused")
	_check(interaction != null and not bool(interaction.call("is_enabled")),
		"T10: interaction component is disabled while paused")
	var npcs_root: Node = game.get_node_or_null("Npcs")
	var frozen_ok: bool = npcs_root != null and npcs_root.get_child_count() > 0
	if frozen_ok:
		for npc_variant in npcs_root.get_children():
			var npc: Npc = npc_variant as Npc
			if npc == null or not npc.is_conversation_busy():
				frozen_ok = false
				break
	_check(frozen_ok, "T11: every NPC is frozen without dropping its goal")

	var expected_buttons: Array = [
		["Box/MenuBox/SaveRow/SaveAsButton", "Save As"],
		["Box/MenuBox/LoadButton", "Load Game"],
		["Box/MenuBox/OptionsButton", "Options"],
		["Box/MenuBox/ModsButton", "Mods Menu"],
		["Box/MenuBox/ResumeButton", "Resume"],
	]
	var labels_ok: bool = true
	for entry in expected_buttons:
		var button: Button = pause.get_node_or_null(str(entry[0])) as Button
		if button == null or button.text != str(entry[1]):
			labels_ok = false
	_check(labels_ok, "T12: Save As / Load / Options / Mods / Resume buttons exist")

	# --- Save As writes a named slot from the live state -----------------------
	var input: LineEdit = pause.get_node_or_null("Box/MenuBox/SaveRow/SlotNameInput") as LineEdit
	var save_button: Button = pause.get_node_or_null("Box/MenuBox/SaveRow/SaveAsButton") as Button
	var status: Label = pause.get_node_or_null("Box/MenuBox/StatusLabel") as Label
	save_button.pressed.emit()
	_check(status != null and status.text.contains("Enter a slot name")
		and not SaveManager.has_slot(SLOT), "T13: an empty slot name is rejected")
	input.text = SaveManager.MANUAL_SLOT
	save_button.pressed.emit()
	_check(status.text.contains("reserved") and not SaveManager.has_slot(SLOT),
		"T14: a reserved slot name is rejected without a bypass")
	input.text = SLOT
	save_button.pressed.emit()
	var saved: SaveGame = SaveManager.load_slot(SLOT)
	var save_ok: bool = (
		saved != null and saved.slot_name == SLOT
		and int(saved.day_snapshot.get("day", 0)) == day_before
		and int(saved.day_snapshot.get("state", -1)) == state_before
	)
	var saved_player: NpcInstance = saved.player_instance as NpcInstance if saved != null else null
	_check(save_ok and saved_player != null and saved_player.template_id == "char:alex",
		"T15: Save As writes a named slot from the live day with template linkage")
	_check(status.text.contains("Saved slot '%s'" % SLOT),
		"T16: the save result is reported in the overlay")

	# --- Load routes out, resumes, and shows the new slot ----------------------
	var load_button: Button = pause.get_node_or_null("Box/MenuBox/LoadButton") as Button
	load_button.pressed.emit()
	await _settle()
	var screen: Node = get_tree().current_scene
	_check(screen != null and screen.name == "LoadGame", "T17: Load routes to the Load Game screen")
	_check(not TimeManager.is_paused(), "T18: the clock resumes before leaving the game")
	var slot_list: VBoxContainer = screen.get_node_or_null("CenterBox/SlotScroll/SlotList") as VBoxContainer
	var listed: bool = false
	if slot_list != null:
		for i in range(slot_list.get_child_count()):
			var meta: Label = slot_list.get_child(i).get_node_or_null("MetaScroll/MetaLabel") as Label
			if meta != null and meta.text.begins_with(SLOT):
				listed = true
				break
	_check(listed, "T19: the slot created from pause appears in the Load Game list")

	# --- Options / Mods are embedded panels that return to pause ---------------
	GameManager.start_fresh_day()
	await _settle()
	game = get_tree().current_scene
	game.set("npc_initiation_enabled", false)
	game.set("class_travel_lead_sec", 0.0)
	pause = game.get_node_or_null("PauseLayer/PauseMenu")
	_send_action(game, "ui_cancel")
	await _frames(2)
	_check(bool(game.call("is_paused")) and bool(pause.call("is_open")),
		"T20: Escape reopens the pause overlay on a fresh day")

	var options_button: Button = pause.get_node_or_null("Box/MenuBox/OptionsButton") as Button
	options_button.pressed.emit()
	await _frames(2)
	var embedded: Node = pause.get_node_or_null("PanelHost/Options")
	_check(str(pause.call("get_embedded_screen_name")) == "Options"
		and embedded != null and not _visible(pause, "Box") and _visible(pause, "PanelHost"),
		"T21: Options embeds in the pause overlay without swapping scenes")
	_embedded_back(embedded)
	await _frames(2)
	_check(str(pause.call("get_embedded_screen_name")) == ""
		and _visible(pause, "Box") and not _visible(pause, "PanelHost")
		and bool(game.call("is_paused")),
		"T22: the embedded Options Back returns to pause")

	var mods_button: Button = pause.get_node_or_null("Box/MenuBox/ModsButton") as Button
	mods_button.pressed.emit()
	await _frames(2)
	embedded = pause.get_node_or_null("PanelHost/ModsMenu")
	_check(str(pause.call("get_embedded_screen_name")) == "ModsMenu"
		and embedded != null and not _visible(pause, "Box"),
		"T23: Mods embeds in the pause overlay")
	_embedded_back(embedded)
	await _frames(2)
	_check(str(pause.call("get_embedded_screen_name")) == "" and _visible(pause, "Box"),
		"T24: the embedded Mods Back returns to pause")

	options_button.pressed.emit()
	await _frames(2)
	_send_action(game, "ui_cancel")
	await _frames(2)
	_check(bool(game.call("is_paused")) and str(pause.call("get_embedded_screen_name")) == ""
		and _visible(pause, "Box"),
		"T25: Escape from an embedded panel goes Back to pause, not to play")

	# --- Escape resumes with no drift -----------------------------------------
	_send_action(game, "ui_cancel")
	await _frames(2)
	_check(not bool(game.call("is_paused")) and not bool(pause.call("is_open")),
		"T26: Escape resumes from the main pause box")
	_check(not TimeManager.is_paused(), "T27: TimeManager resumes the clock")
	player = game.get_node_or_null("Player") as Node2D
	interaction = game.get_node_or_null("Player/InteractionComponent")
	_check(player != null and not bool(player.call("is_input_locked"))
		and interaction != null and bool(interaction.call("is_enabled")),
		"T28: input and interaction are restored on resume")
	npcs_root = game.get_node_or_null("Npcs")
	var unfrozen_ok: bool = npcs_root != null
	if unfrozen_ok:
		for npc_variant in npcs_root.get_children():
			var npc: Npc = npc_variant as Npc
			if npc != null and npc.is_conversation_busy():
				unfrozen_ok = false
				break
	_check(unfrozen_ok, "T29: NPCs are unfrozen on resume")
	var elapsed_after: float = TimeManager.get_phase_elapsed()
	TimeManager.advance(1.0)
	_check(is_equal_approx(TimeManager.get_phase_elapsed(), elapsed_after + 1.0),
		"T30: the clock resumes from its saved phase time without drift")

	# --- The conversation owns Escape; overlays never overlap -----------------
	var ui: Node = game.get_node_or_null("DialogueLayer/ConversationUI")
	var target: Npc = (npcs_root.get_child(0) as Npc) if npcs_root != null and npcs_root.get_child_count() > 0 else null
	if player != null and target != null:
		player.global_position = target.global_position + Vector2(12.0, 0.0)
	await _frames(4)
	_send_key(interaction, KEY_E)
	await _frames(3)
	_check(ui != null and bool(ui.call("is_open")) and not bool(pause.call("is_open")),
		"T31: E opens the conversation with no pause overlay on top")
	_send_action(game, "ui_cancel")
	await _frames(2)
	_check(not bool(pause.call("is_open")) and not bool(game.call("is_paused")),
		"T32: Escape to Game while talking never opens pause")
	_check(bool(ui.call("is_open")) and bool(game.call("is_conversation_open")),
		"T33: the conversation stays open when Game ignores Esc")
	_send_action(ui, "ui_cancel")
	await _frames(2)
	_check(not bool(ui.call("is_open")) and not bool(game.call("is_conversation_open")),
		"T34: the conversation cancels on its own Escape")

	# One Escape delivered in real tree order: ConversationUI first, then Game.
	# Both handlers see the same event, which direct-call tests otherwise miss.
	_send_key(interaction, KEY_E)
	await _frames(3)
	var shared_escape := InputEventAction.new()
	shared_escape.action = "ui_cancel"
	shared_escape.pressed = true
	ui.call("_unhandled_input", shared_escape)
	game.call("_unhandled_input", shared_escape)
	await _frames(2)
	_check(not bool(game.call("is_paused")) and not bool(pause.call("is_open"))
		and not bool(game.call("is_conversation_open")),
		"T34b: one Esc consumed by the conversation never opens pause")

	_send_action(game, "ui_cancel")
	await _frames(2)
	_check(bool(game.call("is_paused")) and bool(pause.call("is_open"))
		and not bool(ui.call("is_open")),
		"T35: pause works again after the talk with no overlap")
	_send_action(game, "ui_cancel")
	await _frames(2)
	_check(not bool(game.call("is_paused")) and not bool(pause.call("is_open")),
		"T36: final Escape resumes cleanly")

	# A focused LineEdit eats ui_cancel in its own gui_input, so the overlay must
	# own Escape in _input before GUI handling (code-review finding 2).
	_send_action(game, "ui_cancel")
	await _frames(2)
	var slot_field: LineEdit = pause.get_node_or_null("Box/MenuBox/SaveRow/SlotNameInput") as LineEdit
	slot_field.text = "typed_but_rejected"
	slot_field.grab_focus()
	var field_escape := InputEventAction.new()
	field_escape.action = "ui_cancel"
	field_escape.pressed = true
	pause.call("_input", field_escape)
	await _frames(2)
	_check(not bool(game.call("is_paused")) and not bool(pause.call("is_open")),
		"T36b: Esc resumes even while the slot-name field owns focus")

	_send_action(game, "ui_cancel")
	await _frames(2)
	var status_after: Label = pause.get_node_or_null("Box/MenuBox/StatusLabel") as Label
	_check(slot_field.text.is_empty() and status_after.text.is_empty(),
		"T36c: a new pause session clears rejected text and status")
	_send_action(game, "ui_cancel")
	await _frames(2)
	_check(_passed == EXPECTED_CHECKS - 1, "T40: every planned check ran")

	_finish()


## --- Helpers ----------------------------------------------------------------

func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("[028] PASS " + label)
	else:
		_failed += 1
		print("[028] FAIL " + label)


func _send_action(node: Node, action: String) -> void:
	if node == null:
		return
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	node.call("_unhandled_input", event)


func _send_key(node: Node, keycode: int) -> void:
	if node == null:
		return
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	node.call("_unhandled_input", event)


func _visible(node: Node, path: String) -> bool:
	var target := node.get_node_or_null(path) as Control
	return target != null and target.visible


func _embedded_back(embedded: Node) -> void:
	if embedded == null:
		return
	var back: Button = embedded.get_node_or_null("CenterBox/BackButton") as Button
	if back != null:
		back.pressed.emit()


func _remove_slot(slot: String) -> void:
	if SaveManager.has_slot(slot):
		SaveManager.delete_slot(slot)


func _finish() -> void:
	TimeManager.set_paused(false)
	_remove_slot(SLOT)
	print("[028] RESULT passed=%d failed=%d" % [_passed, _failed])
	if _failed == 0 and _passed == EXPECTED_CHECKS:
		print("ALL_028_CHECKS_PASSED")
	else:
		print("SOME_028_CHECKS_FAILED")
	get_tree().quit(0 if _failed == 0 and _passed == EXPECTED_CHECKS else 1)
