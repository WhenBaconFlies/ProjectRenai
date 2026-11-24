## LoadGame
##
## Player-facing Load Game screen (ticket 027). Lists every slot on disk with
## readable metadata (day, period, save time, NPC count), loads the chosen slot
## through GameManager, and deletes a slot after an inline confirmation.
##
## Creation is deliberately absent here: a named slot is written from the
## in-game pause overlay (ticket 028) because the Main Menu has no live state.
## F5/F9 stay in Game.gd and are untouched by this screen.

extends Control

## Row names are stable so headless harnesses can drive the real buttons by
## node path: CenterBox/SlotScroll/SlotList/SlotRow_<index>/LoadButton, etc.
const SLOT_ROW_PREFIX: String = "SlotRow_"
const NO_SLOTS_TEXT: String = "No saved games yet — create one from the pause menu while playing."
const READY_TEXT: String = "Select a slot to load or delete."

## Ticket 028: when this screen is embedded in the pause overlay, Back returns
## to pause instead of leaving the live game. Invalid callables restore the
## normal Main Menu route (mirrors MainMenu.set_quit_action / PlaceholderScreen).
var back_action: Callable = Callable()

@onready var _slot_list: VBoxContainer = $CenterBox/SlotScroll/SlotList
@onready var _status_label: Label = $CenterBox/StatusLabel
@onready var _back_button: Button = $CenterBox/BackButton

## Dictionaries with keys: slot, row, meta, load_button, delete_button,
## cancel_button. Rebuilt from disk on every refresh().
var _rows: Array = []
## Slot currently armed for deletion ("" when none). Only one row at a time.
var _pending_delete: String = ""
## Cached one-line descriptions keyed by slot id. Reading metadata requires a
## full SaveGame deserialization, so unchanged slots are not re-read on every
## row rebuild (delete/cancel) — SaveManager allows an unlimited number of slots.
var _metadata_cache: Dictionary = {}


func _ready() -> void:
	_back_button.pressed.connect(_on_back_pressed)
	refresh()


## Rebuild the slot list from SaveManager. Public so a harness can call it after
## seeding/removing slots without having to leave and re-enter the scene.
func refresh() -> void:
	_pending_delete = ""
	_clear_rows()
	var slots: Array[String] = SaveManager.list_slots()
	var present: Dictionary = {}
	for slot in slots:
		present[slot] = true
	for key in _metadata_cache.keys():
		if not present.has(key):
			_metadata_cache.erase(key)
	if slots.is_empty():
		_status_label.text = NO_SLOTS_TEXT
		return
	_status_label.text = READY_TEXT
	for index in range(slots.size()):
		_add_row(index, slots[index])


## Slot ids currently shown, in list order. Handy for headless verification.
func get_slot_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry in _rows:
		ids.append(str(entry["slot"]))
	return ids


## --- Row construction -------------------------------------------------------

func _add_row(index: int, slot: String) -> void:
	var row := HBoxContainer.new()
	row.name = "%s%d" % [SLOT_ROW_PREFIX, index]
	row.custom_minimum_size = Vector2(0, 38)
	row.add_theme_constant_override("separation", 8)

	# Only the description gets its own horizontal scroll area. The outer
	# SlotScroll has horizontal scrolling disabled, so the buttons below stay
	# visible no matter how long a slot id/description is.
	var meta_scroll := ScrollContainer.new()
	meta_scroll.name = "MetaScroll"
	meta_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	meta_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	meta_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var meta := Label.new()
	meta.name = "MetaLabel"
	if not _metadata_cache.has(slot):
		_metadata_cache[slot] = _metadata_text(slot)
	meta.text = str(_metadata_cache[slot])
	meta.tooltip_text = meta.text
	meta_scroll.add_child(meta)

	var load_button := Button.new()
	load_button.name = "LoadButton"
	load_button.text = "Load"
	load_button.custom_minimum_size = Vector2(78, 0)
	load_button.pressed.connect(_on_load_pressed.bind(slot))

	var delete_button := Button.new()
	delete_button.name = "DeleteButton"
	delete_button.text = "Delete"
	delete_button.custom_minimum_size = Vector2(88, 0)
	delete_button.pressed.connect(_on_delete_pressed.bind(slot))

	var cancel_button := Button.new()
	cancel_button.name = "CancelButton"
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(72, 0)
	cancel_button.visible = false
	cancel_button.pressed.connect(_on_cancel_pressed)

	row.add_child(meta_scroll)
	row.add_child(load_button)
	row.add_child(delete_button)
	row.add_child(cancel_button)
	_slot_list.add_child(row)
	_rows.append({
		"slot": slot,
		"row": row,
		"meta": meta,
		"load_button": load_button,
		"delete_button": delete_button,
		"cancel_button": cancel_button,
	})


## Build the readable one-line description from the persisted payload. A slot
## that fails validation is still listed and remains deletable.
func _metadata_text(slot: String) -> String:
	var save: SaveGame = SaveManager.load_slot(slot)
	if save == null:
		return "%s  —  unreadable save (%s)" % [slot, SaveManager.get_last_error()]
	var snapshot: Dictionary = save.day_snapshot
	var day: int = int(snapshot.get("day", 0))
	var state_index: int = int(snapshot.get("state", -1))
	var state_name: String = "UNKNOWN"
	var keys: Array = TimeManager.DayState.keys()
	if state_index >= 0 and state_index < keys.size():
		state_name = str(keys[state_index])
	var saved_at: String = "unknown time"
	if save.saved_at > 0:
		saved_at = Time.get_datetime_string_from_unix_time(int(save.saved_at / 1000), true)
	var npc_count: int = 0
	if save.npc_instances is Array:
		npc_count = (save.npc_instances as Array).size()
	return "%s  —  Day %d · %s · %s · %d NPCs" % [
		slot, day, state_name, saved_at, npc_count
	]


func _clear_rows() -> void:
	for entry in _rows:
		var row: Node = entry["row"] as Node
		if is_instance_valid(row):
			_slot_list.remove_child(row)
			row.queue_free()
	_rows.clear()


## --- Button handlers --------------------------------------------------------

func _on_load_pressed(slot: String) -> void:
	# GameManager owns validation, current_save and the scene swap. A failure
	# leaves this screen up so the player can try another slot.
	if not GameManager.load_slot(slot):
		_status_label.text = "Could not load '%s': %s" % [slot, SaveManager.get_last_error()]


## Two-step confirm: first press arms the row, second press deletes. Pressing a
## different row's Delete moves the pending state instead of deleting two slots.
func _on_delete_pressed(slot: String) -> void:
	if _pending_delete == slot:
		var message: String
		if SaveManager.delete_slot(slot):
			message = "Deleted slot '%s'." % slot
		else:
			message = "Could not delete '%s': %s" % [slot, SaveManager.get_last_error()]
		refresh()
		_status_label.text = message
		return

	_reset_delete_rows()
	_pending_delete = slot
	for entry in _rows:
		if str(entry["slot"]) == slot:
			(entry["delete_button"] as Button).text = "Confirm Delete?"
			(entry["cancel_button"] as Button).visible = true
			break
	_status_label.text = "Press Confirm Delete again, or Cancel, for '%s'." % slot


func _on_cancel_pressed() -> void:
	var message: String = ""
	if not _pending_delete.is_empty():
		message = "Deletion cancelled for '%s'." % _pending_delete
	refresh()
	_status_label.text = message


func _reset_delete_rows() -> void:
	for entry in _rows:
		(entry["delete_button"] as Button).text = "Delete"
		(entry["cancel_button"] as Button).visible = false


func set_back_action(action: Callable) -> void:
	back_action = action if action.is_valid() else Callable(self, "_default_back")


func _on_back_pressed() -> void:
	var action: Callable = back_action if back_action.is_valid() else Callable(self, "_default_back")
	action.call()


func _default_back() -> void:
	GameManager.show_main_menu()
