## SaveManager
##
## Global singleton responsible for save/load, slot management, and
## instance<->template linkage by stable template IDs. Ticket 017 turns this stub
## into a real Godot Resource save system:
##   - one `.tres` file per named slot under `user://saves/` (no slot cap);
##   - `autosave()` writes the reserved `autosave` slot at DayEnd;
##   - `save_slot()` / `load_slot()` are the public API used by the F5/F9 debug
##     hotkeys and by headless verification;
##   - a `SaveGame` payload is validated (version) before any state is applied.
##
## Serialization stays out of Game.gd: an optional state-provider Callable
## supplies the live player/NPC instances and the feedback toggle, while the day
## snapshot comes from TimeManager (or is passed in by the caller).


extends Node

## File conventions. Slot ids are sanitized strings, so the number of slots is
## limited only by the filesystem, not by code.
const SAVE_DIR: String = "user://saves/"
const SAVE_EXTENSION: String = ".tres"
const AUTOSAVE_SLOT: String = "autosave"
const MANUAL_SLOT: String = "manual"

## Game.gd registers this so the autoload never reaches into scene nodes itself.
var _state_provider: Callable = Callable()

## Human-readable reason for the most recent failed operation ("" on success).
var _last_error: String = ""


func _ready() -> void:
	_ensure_save_dir()


## --- Provider seam ----------------------------------------------------------

## Install (or clear, with Callable()) the callback returning
## { player_instance, npc_instances, show_relationship_feedback }.
func set_state_provider(provider: Callable) -> void:
	_state_provider = provider if provider.is_valid() else Callable()


func has_state_provider() -> bool:
	return _state_provider.is_valid()


## --- Slot API ---------------------------------------------------------------

## DayEnd hook kept from ticket 011. Writes the reserved autosave slot and
## returns success so callers/tests can observe it (TimeManager ignores it).
func autosave(snapshot: Dictionary = {}) -> bool:
	return save_slot(AUTOSAVE_SLOT, snapshot, true)


## Write the current game state to `slot_name`. An explicit `day_snapshot` avoids
## a runtime lookup in headless tests; otherwise TimeManager supplies it.
## `allow_reserved` is the internal bypass used by autosave and the F5 handler;
## general callers cannot overwrite the autosave/manual checkpoints.
## Returns false (with get_last_error() populated) on any recoverable failure.
func save_slot(slot_name: String, day_snapshot: Dictionary = {}, allow_reserved: bool = false) -> bool:
	var slot: String = _sanitize_slot(slot_name)
	if not allow_reserved and (slot.to_lower() == AUTOSAVE_SLOT or slot.to_lower() == MANUAL_SLOT):
		_fail("slot name '%s' is reserved" % slot_name)
		return false
	var payload: SaveGame = _collect_state(slot, day_snapshot, _next_write_seq())
	if payload == null:
		return false

	_ensure_save_dir()
	var path: String = get_save_path(slot)
	var err: int = ResourceSaver.save(payload, path)
	if err != OK:
		_fail("could not write save '%s' (error %d)" % [path, err])
		return false

	_last_error = ""
	print("[SaveManager] saved slot '%s' to %s" % [slot, path])
	return true


## Load and validate a slot. Returns null on a missing/incompatible/corrupt save
## after logging and setting get_last_error() — never crashes and never mutates
## live game state; the caller (GameManager) decides what to do with the result.
func load_slot(slot_name: String) -> SaveGame:
	var slot: String = _sanitize_slot(slot_name)
	var path: String = get_save_path(slot)
	if not FileAccess.file_exists(path):
		_fail("save slot '%s' does not exist (%s)" % [slot, path])
		return null

	var resource: Resource = ResourceLoader.load(path)
	if not (resource is SaveGame):
		_fail("save slot '%s' is not a SaveGame resource" % slot)
		return null
	var save: SaveGame = resource as SaveGame
	if not save.is_compatible():
		_fail("save slot '%s' has version %d (this build supports up to %d)" % [
			slot, save.version, SaveGame.CURRENT_VERSION
		])
		return null
	if not save.is_well_formed():
		_fail("save slot '%s' has a malformed payload" % slot)
		return null
	if save.version < SaveGame.CURRENT_VERSION:
		push_warning("[SaveManager] loading older save version %d from slot '%s'" % [save.version, slot])

	_last_error = ""
	return save


## All slot names currently on disk, sorted. No cap — unlimited slots.
func list_slots() -> Array[String]:
	var slots: Array[String] = []
	_ensure_save_dir()
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		_fail("cannot open save directory '%s' (error %d)" % [SAVE_DIR, DirAccess.get_open_error()])
		return slots
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.ends_with(SAVE_EXTENSION):
			slots.append(entry.substr(0, entry.length() - SAVE_EXTENSION.length()))
		entry = dir.get_next()
	dir.list_dir_end()
	slots.sort()
	return slots


func has_slot(slot_name: String) -> bool:
	return FileAccess.file_exists(get_save_path(slot_name))


## Delete a slot. Returns false when the file is absent or cannot be removed.
func delete_slot(slot_name: String) -> bool:
	var path: String = get_save_path(slot_name)
	if not FileAccess.file_exists(path):
		_fail("save slot '%s' does not exist" % slot_name)
		return false
	var err: int = DirAccess.remove_absolute(path)
	if err != OK:
		_fail("could not delete save '%s' (error %d)" % [path, err])
		return false
	_last_error = ""
	return true


## Most recently written compatible slot, for the F9 hotkey. The monotonic
## write_seq wins; saved_at and the slot name are only secondary tie-breakers so
## two writes within one millisecond cannot pick the wrong slot.
func get_last_saved_slot() -> String:
	var previous_error: String = _last_error
	var best: String = ""
	var best_seq: int = -1
	var best_time: int = -1
	for slot in list_slots():
		var save: SaveGame = load_slot(slot)
		if save == null:
			continue
		var newer: bool = (
			save.write_seq > best_seq
			or (save.write_seq == best_seq and (
				save.saved_at > best_time
				or (save.saved_at == best_time and (best.is_empty() or slot < best))
			))
		)
		if newer:
			best = slot
			best_seq = save.write_seq
			best_time = save.saved_at
	_last_error = previous_error
	return best


func get_last_error() -> String:
	return _last_error


## Resolved path for a slot id (sanitized, `.tres` appended).
func get_save_path(slot_name: String) -> String:
	return SAVE_DIR + _sanitize_slot(slot_name) + SAVE_EXTENSION


## --- Internals --------------------------------------------------------------

## Build a SaveGame from the provider payload plus the day snapshot. Instances
## are deep-copied inside SaveGame.from_state(), so live state can keep changing
## while the payload is written without corrupting it.
func _collect_state(slot: String, day_snapshot: Dictionary, write_seq: int) -> SaveGame:
	var provided: Dictionary = {}
	if _state_provider.is_valid():
		var result: Variant = _state_provider.call()
		if result is Dictionary:
			provided = result

	var snapshot: Dictionary = day_snapshot
	if snapshot.is_empty():
		snapshot = _time_snapshot()

	var player: Variant = provided.get("player_instance", null)
	var npcs: Variant = provided.get("npc_instances", [])
	var npc_array: Array = []
	if npcs is Array:
		npc_array = npcs as Array
	return SaveGame.from_state(
		slot,
		snapshot,
		player as NpcInstance,
		npc_array,
		bool(provided.get("show_relationship_feedback", true)),
		write_seq
	)


## One higher than the largest write_seq currently on disk. Loads only valid
## slots; a corrupt slot must not bump the counter or block new saves.
func _next_write_seq() -> int:
	var max_seq: int = 0
	for slot in list_slots():
		var save: SaveGame = load_slot(slot)
		if save != null and save.write_seq > max_seq:
			max_seq = save.write_seq
	return max_seq + 1


func _time_snapshot() -> Dictionary:
	var manager: Node = _scene_node("TimeManager")
	if manager != null and manager.has_method("get_day_snapshot"):
		var snapshot: Variant = manager.call("get_day_snapshot")
		if snapshot is Dictionary:
			return snapshot
	return {}


## Restrict slot ids to safe filename characters. Path separators become '_', so
## a slot name can never escape SAVE_DIR. When the raw name had to be changed,
## append a short hash so distinct names (e.g. "a/b" and "a b") cannot silently
## collide on the same file. Length is capped only for filesystem sanity;
## arbitrary ids still mean unlimited slots.
func _sanitize_slot(raw: String) -> String:
	var cleaned: String = ""
	for character in raw:
		if (
			(character >= "a" and character <= "z")
			or (character >= "A" and character <= "Z")
			or (character >= "0" and character <= "9")
			or character == "_" or character == "-"
		):
			cleaned += character
		else:
			cleaned += "_"
	var was_changed: bool = cleaned != raw
	if cleaned.is_empty():
		cleaned = "slot"
	if cleaned.length() > 55:
		cleaned = cleaned.substr(0, 55)
	if was_changed:
		# String.hash() is available in Godot 4.2 (String.md5() is not).
		cleaned = cleaned + "_" + ("%08x" % (absi(raw.hash()) % 0x100000000))
	return cleaned


func _ensure_save_dir() -> void:
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir != null:
		return
	var err: int = DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if err != OK:
		push_warning("[SaveManager] cannot create save directory '%s' (error %d)" % [SAVE_DIR, err])


func _scene_node(name: String) -> Node:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null(NodePath(name))


func _fail(message: String) -> void:
	_last_error = message
	push_warning("[SaveManager] " + message)
