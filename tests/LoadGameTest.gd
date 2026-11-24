## LoadGameTest
##
## Persistent headless acceptance harness for ticket 027. Drives the real Load
## Game screen through GameManager routes and its own buttons, asserting external
## behavior only: slot listing with readable day/state metadata, two-step delete
## with Cancel, loading into a restored day with template linkage, the absence of
## any live-state creation control on the menu, and the F5/F9 debug hotkeys.
## Prints ALL_027_CHECKS_PASSED only when every assertion passed.
extends Node

const EXPECTED_CHECKS: int = 35
const SLOT_A: String = "load_ui_alpha"
const SLOT_B: String = "load_ui_beta"
const CORRUPT_SLOT: String = "load_ui_corrupt"
const LONG_PREFIX: String = "zzlong"

var _passed: int = 0
var _failed: int = 0
var _saved_a: SaveGame = null
var _had_manual: bool = false
var _manual_backup: PackedByteArray = PackedByteArray()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _settle()
	_remove_slot(SLOT_A)
	_remove_slot(SLOT_B)
	_remove_slot(CORRUPT_SLOT)
	_remove_slots_with_prefix(LONG_PREFIX)
	_backup_manual()

	# --- Seed two slots from a live day through the real SaveManager ----------
	GameManager.start_fresh_day()
	await _settle()
	var game: Node = get_tree().current_scene
	_check(game != null and game.name == "Game",
		"T1: a fresh day boots so SaveManager has a live state provider")

	# Both slots use a free-time state so the saved in-flight goals are still
	# meaningful after load. Position comparison allows sub-pixel drift from the
	# live AI during the harness's settle frames.
	var snapshot_a: Dictionary = TimeManager.get_day_snapshot()
	snapshot_a["day"] = 7
	snapshot_a["state"] = TimeManager.DayState.FREETIME1
	var snapshot_b: Dictionary = TimeManager.get_day_snapshot()
	snapshot_b["day"] = 3
	snapshot_b["state"] = TimeManager.DayState.PERIOD2
	_check(SaveManager.save_slot(SLOT_A, snapshot_a),
		"T2: seed slot A (day 7, FREETIME1) through SaveManager")
	_check(SaveManager.save_slot(SLOT_B, snapshot_b),
		"T3: seed slot B (day 3, PERIOD2) through SaveManager")
	_saved_a = SaveManager.load_slot(SLOT_A)
	_check(_saved_a != null and _saved_a.is_well_formed()
		and int(_saved_a.day_snapshot.get("day", 0)) == 7,
		"T4: seeded slot A is a well-formed SaveGame with the authored day")

	# A long raw name with an invalid char past the truncation point must survive
	# the list_slots() -> load_slot() round-trip the UI depends on.
	var long_raw: String = LONG_PREFIX + "a".repeat(52) + "/"
	var long_saved: bool = SaveManager.save_slot(long_raw, snapshot_a)
	var long_reloadable: bool = false
	if long_saved:
		for listed_slot in SaveManager.list_slots():
			if str(listed_slot).begins_with(LONG_PREFIX):
				long_reloadable = SaveManager.load_slot(str(listed_slot)) != null
				break
	_check(long_saved and long_reloadable,
		"T4b: a long sanitized slot id round-trips through list_slots()")

	_seed_corrupt_slot()

	# --- Real Main Menu -> Load Game route ------------------------------------
	GameManager.show_main_menu()
	await _settle()
	var menu: Node = get_tree().current_scene
	var menu_load: Button = menu.get_node_or_null("CenterBox/LoadGameButton") as Button
	if menu_load != null:
		menu_load.pressed.emit()
	await _settle()
	var screen: Node = get_tree().current_scene
	_check(screen != null and screen.name == "LoadGame",
		"T5: Main Menu's Load Game button enters the real LoadGame scene")
	if screen == null:
		_finish()
		return

	var title := screen.get_node_or_null("CenterBox/TitleLabel") as Label
	_check(title != null and title.text == "Load Game",
		"T6: screen still carries the Load Game title")
	var info := screen.get_node_or_null("CenterBox/InfoLabel") as Label
	_check(info != null and info.text.contains("Pause menu"),
		"T7: screen explains named slots are created from the pause menu")
	var buttons: Array = []
	_collect_buttons(screen, buttons)
	var has_creation_control: bool = false
	for button_variant in buttons:
		var button: Button = button_variant as Button
		var label: String = button.text.to_lower()
		if label.contains("save") or label.contains("create") or label.contains("new game"):
			has_creation_control = true
	_check(not has_creation_control,
		"T8: no live-state creation control exists on the Load Game menu")

	var slot_list := screen.get_node_or_null("CenterBox/SlotScroll/SlotList") as VBoxContainer
	var disk_slots: Array[String] = SaveManager.list_slots()
	_check(slot_list != null and slot_list.get_child_count() == disk_slots.size(),
		"T9: every on-disk slot gets one row")
	if slot_list == null:
		_finish()
		return

	# --- Layout: the description scrolls, the action buttons never do ---------
	var outer_scroll := screen.get_node_or_null("CenterBox/SlotScroll") as ScrollContainer
	_check(outer_scroll != null
		and outer_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"T9a: the slot list itself never scrolls horizontally")
	var long_row := _find_row(slot_list, LONG_PREFIX)
	var meta_scroll: ScrollContainer = null
	if long_row != null:
		meta_scroll = long_row.get_node_or_null("MetaScroll") as ScrollContainer
	_check(meta_scroll != null
		and meta_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO
		and meta_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"T9b: a long description gets its own horizontal-only scroll area")
	if meta_scroll != null and outer_scroll != null and long_row != null:
		var load_rect: Rect2 = (long_row.get_node_or_null("LoadButton") as Button).get_global_rect()
		var delete_rect: Rect2 = (long_row.get_node_or_null("DeleteButton") as Button).get_global_rect()
		var view_rect: Rect2 = outer_scroll.get_global_rect()
		_check(load_rect.position.x >= view_rect.position.x - 1.0
			and delete_rect.end.x <= view_rect.end.x + 1.0,
			"T9c: Load and Delete stay visible for a long slot description")

	var row_a := _find_row(slot_list, SLOT_A)
	var row_b := _find_row(slot_list, SLOT_B)
	_check(row_a != null and _meta_text(row_a).contains(SLOT_A)
		and _meta_text(row_a).contains("Day 7") and _meta_text(row_a).contains("FREETIME1"),
		"T10: slot A row shows the slot id and readable day/state metadata")
	_check(row_b != null and _meta_text(row_b).contains(SLOT_B)
		and _meta_text(row_b).contains("Day 3") and _meta_text(row_b).contains("PERIOD2"),
		"T11: slot B row shows the slot id and readable day/state metadata")

	# --- Decision behaviors: unreadable slot, failed load, cross-row confirm ---
	var corrupt_row := _find_row(slot_list, CORRUPT_SLOT)
	_check(corrupt_row != null and _meta_text(corrupt_row).contains("unreadable"),
		"T11a: an unreadable slot is still listed with a clear marker")
	if corrupt_row == null:
		_finish()
		return
	var corrupt_load: Button = corrupt_row.get_node_or_null("LoadButton") as Button
	var status_label := screen.get_node_or_null("CenterBox/StatusLabel") as Label
	corrupt_load.pressed.emit()
	_check(status_label != null and status_label.text.contains("Could not load")
		and status_label.text.contains(CORRUPT_SLOT),
		"T11b: Load on an unreadable slot reports the SaveManager error")
	var delete_a: Button = row_a.get_node_or_null("DeleteButton") as Button
	delete_a.pressed.emit()
	var delete_b_cross: Button = row_b.get_node_or_null("DeleteButton") as Button
	delete_b_cross.pressed.emit()
	_check(SaveManager.has_slot(SLOT_A) and delete_a.text == "Delete"
		and delete_b_cross.text == "Confirm Delete?",
		"T11c: arming a different row moves the pending delete instead of deleting both")
	var cancel_b_cross: Button = row_b.get_node_or_null("CancelButton") as Button
	cancel_b_cross.pressed.emit()

	# --- Two-step delete with Cancel ------------------------------------------
	var delete_b: Button = row_b.get_node_or_null("DeleteButton") as Button
	var cancel_b: Button = row_b.get_node_or_null("CancelButton") as Button
	delete_b.pressed.emit()
	_check(SaveManager.has_slot(SLOT_B) and delete_b.text == "Confirm Delete?"
		and cancel_b.visible,
		"T12: first Delete press arms confirmation without deleting")
	cancel_b.pressed.emit()
	delete_b = _find_row(slot_list, SLOT_B).get_node_or_null("DeleteButton") as Button
	var cancel_after: Button = _find_row(slot_list, SLOT_B).get_node_or_null("CancelButton") as Button
	_check(SaveManager.has_slot(SLOT_B) and delete_b.text == "Delete"
		and not cancel_after.visible,
		"T13: Cancel aborts the delete and restores the row")
	var rows_before_delete: int = slot_list.get_child_count()
	delete_b.pressed.emit()
	delete_b = _find_row(slot_list, SLOT_B).get_node_or_null("DeleteButton") as Button
	delete_b.pressed.emit()
	_check(not SaveManager.has_slot(SLOT_B)
		and slot_list.get_child_count() == rows_before_delete - 1,
		"T14: second Delete press removes the slot and its row")
	var corrupt_delete: Button = _find_row(slot_list, CORRUPT_SLOT).get_node_or_null("DeleteButton") as Button
	corrupt_delete.pressed.emit()
	corrupt_delete = _find_row(slot_list, CORRUPT_SLOT).get_node_or_null("DeleteButton") as Button
	corrupt_delete.pressed.emit()
	_check(not SaveManager.has_slot(CORRUPT_SLOT)
		and _find_row(slot_list, CORRUPT_SLOT) == null,
		"T14a: an unreadable slot can still be deleted from the screen")

	# --- Back route still works ------------------------------------------------
	var back := screen.get_node_or_null("CenterBox/BackButton") as Button
	back.pressed.emit()
	await _settle()
	_check(get_tree().current_scene != null and get_tree().current_scene.name == "MainMenu",
		"T15: Back returns to the Main Menu")

	# --- Load a slot: restored day, meters/positions, template linkage ---------
	GameManager.show_load_game()
	await _settle()
	screen = get_tree().current_scene
	slot_list = screen.get_node_or_null("CenterBox/SlotScroll/SlotList") as VBoxContainer
	var row_a2 := _find_row(slot_list, SLOT_A)
	var load_a: Button = row_a2.get_node_or_null("LoadButton") as Button
	load_a.pressed.emit()
	await _settle()
	var loaded_game: Node = get_tree().current_scene
	_check(loaded_game != null and loaded_game.name == "Game",
		"T16: Load enters Game.tscn")
	if loaded_game == null:
		_finish()
		return
	var loaded_save: SaveGame = GameManager.current_save as SaveGame
	_check(loaded_save != null and loaded_save.slot_name == SLOT_A,
		"T17: GameManager holds the selected slot as current_save")
	_check(TimeManager.get_day_number() == 7,
		"T18: the saved day number is restored")
	_check(TimeManager.get_state_name() == "FREETIME1",
		"T19: the saved day state is restored")

	var restored_player: NpcInstance = loaded_game.get("_player_instance") as NpcInstance
	_check(restored_player != null and restored_player.template_id == "char:alex"
		and restored_player.resolve_template() != null,
		"T20: player instance keeps its shipped char:alex template linkage")
	_check(_instances_match(restored_player, _saved_a.player_instance),
		"T21: player stats/mood/meters/position restored identically")

	var restored_npcs: Array = _game_npcs(loaded_game)
	var saved_npcs: Array = _saved_a.npc_instances
	var npcs_match: bool = restored_npcs.size() == saved_npcs.size()
	if npcs_match:
		for index in range(saved_npcs.size()):
			var saved_npc: NpcInstance = saved_npcs[index] as NpcInstance
			var live_npc: NpcInstance = null
			for entry in restored_npcs:
				if (entry as NpcInstance).instance_id == saved_npc.instance_id:
					live_npc = entry as NpcInstance
					break
			if not _instances_match(live_npc, saved_npc):
				npcs_match = false
				break
	_check(npcs_match,
		"T22: every NPC instance restores identically by stable id")

	# --- F5/F9 still work during play -----------------------------------------
	# Back up any pre-existing manual slot first so verification never destroys
	# developer data; the backup is restored in _finish().
	loaded_game.call("_unhandled_input", _action_event("manual_save"))
	_check(SaveManager.has_slot(SaveManager.MANUAL_SLOT),
		"T23: F5 still writes the reserved manual slot during play")
	var manual_save: SaveGame = SaveManager.load_slot(SaveManager.MANUAL_SLOT)
	_check(manual_save != null and int(manual_save.day_snapshot.get("day", 0)) == 7,
		"T24: F5's manual slot captures the live restored day")
	loaded_game.call("_unhandled_input", _action_event("manual_load"))
	await _settle()
	var f9_game: Node = get_tree().current_scene
	var f9_save: SaveGame = GameManager.current_save as SaveGame
	_check(f9_game != null and f9_game.name == "Game",
		"T25: F9 reloads back into Game.tscn")
	_check(f9_save != null and f9_save.slot_name == SaveManager.MANUAL_SLOT
		and TimeManager.get_day_number() == 7,
		"T26: F9 loads the most recently written slot with its day restored")
	_check(_passed + _failed == EXPECTED_CHECKS - 1,
		"T27: every planned check ran")

	_finish()


## --- Helpers ----------------------------------------------------------------

func _settle() -> void:
	# change_scene() defers _do_change_scene, and change_scene_to_file defers
	# again to end of frame. Three idle frames makes scene assertions stable.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("[027] PASS " + label)
	else:
		_failed += 1
		print("[027] FAIL " + label)


func _finish() -> void:
	# Leave no test fixtures behind. A pre-existing manual slot is restored
	# byte-for-byte; an absent one is removed.
	_restore_manual()
	_remove_slot(SLOT_A)
	_remove_slot(SLOT_B)
	_remove_slot(CORRUPT_SLOT)
	_remove_slots_with_prefix(LONG_PREFIX)
	print("[027] RESULT passed=%d failed=%d" % [_passed, _failed])
	if _failed == 0 and _passed == EXPECTED_CHECKS:
		print("ALL_027_CHECKS_PASSED")
	else:
		print("SOME_027_CHECKS_FAILED")
	get_tree().quit(0 if _failed == 0 and _passed == EXPECTED_CHECKS else 1)


func _action_event(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _collect_buttons(node: Node, result: Array) -> void:
	if node is Button:
		result.append(node as Button)
	for child in node.get_children():
		_collect_buttons(child, result)


func _find_row(list: Node, slot: String) -> Node:
	for index in range(list.get_child_count()):
		var row: Node = list.get_child(index)
		var meta := row.get_node_or_null("MetaScroll/MetaLabel") as Label
		if meta != null and meta.text.begins_with(slot):
			return row
	return null


func _meta_text(row: Node) -> String:
	var meta := row.get_node_or_null("MetaScroll/MetaLabel") as Label
	return meta.text if meta != null else ""


func _game_npcs(game: Node) -> Array:
	var instances: Array = []
	for npc_variant in (game.get("_npcs") as Array):
		var npc: Node = npc_variant as Node
		if npc == null:
			continue
		var instance: NpcInstance = npc.get("instance") as NpcInstance
		if instance != null:
			instances.append(instance)
	return instances


func _instances_match(live: NpcInstance, saved: NpcInstance) -> bool:
	if live == null or saved == null:
		return false
	if live.instance_id != saved.instance_id or live.template_id != saved.template_id:
		return false
	if live.stats != saved.stats or live.mood != saved.mood or live.meters != saved.meters:
		return false
	if live.schedule != saved.schedule or live.current_goal != saved.current_goal:
		return false
	# Sub-pixel tolerance: the harness waits settle frames after the scene swap,
	# so a free-time AI tick may nudge an NPC by a few hundredths of a pixel.
	return live.position.distance_to(saved.position) <= 0.05


func _seed_corrupt_slot() -> void:
	var path: String = SaveManager.get_save_path(CORRUPT_SLOT)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		# A valid Resource that is not a SaveGame: exercises load_slot()'s type
		# rejection without the parse-error noise of malformed .tres text.
		file.store_string("[gd_resource type=\"Resource\" load_steps=1 format=3]\n\n[resource]\n")
		file.close()


func _remove_slot(slot: String) -> void:
	if SaveManager.has_slot(slot):
		SaveManager.delete_slot(slot)


func _remove_slots_with_prefix(prefix: String) -> void:
	for slot in SaveManager.list_slots():
		if str(slot).begins_with(prefix):
			SaveManager.delete_slot(str(slot))


func _backup_manual() -> void:
	var path: String = SaveManager.get_save_path(SaveManager.MANUAL_SLOT)
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	_manual_backup = file.get_buffer(file.get_length())
	file.close()
	_had_manual = true


func _restore_manual() -> void:
	var path: String = SaveManager.get_save_path(SaveManager.MANUAL_SLOT)
	if _had_manual:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_manual_backup)
			file.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
