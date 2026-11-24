## GameManager
##
## Global singleton holding overall game state: the currently loaded save,
## scene-transition requests, and the "fresh start / no save" path exercised
## by DebugStart. Behaviour is filled in by later tickets (day loop, scenes);
## this is the stable entry point other systems talk to.
extends Node

## The currently loaded save resource. `null` means "no save / fresh start",
## which is the default state DebugStart exercises.
var current_save = null

## Path of the scene currently considered "active" (informational).
var current_scene_path: String = ""


func _ready() -> void:
	# Fresh start is the default: no save to restore, no crash.
	current_save = null


## Begin a fresh day with no save present. Loads Game.tscn.
## Called by the DebugStart launcher so the slice is runnable immediately.
func start_fresh_day() -> void:
	current_save = null
	# The Game scene starts the clock in its own _ready(), after all of its
	# children (and their listeners) exist. change_scene_to_file() defers the
	# swap past this call, so starting here would emit day_started too early.
	change_scene("res://scenes/Game.tscn")


## Load a saved day and enter Game.tscn. SaveManager validates the slot and
## returns a SaveGame (or null on a recoverable error); storing it in
## current_save is the signal Game.gd uses to take its restore branch instead of
## starting a fresh day. A failed load leaves the current game untouched.
func load_slot(slot_name: String) -> bool:
	var save: SaveGame = SaveManager.load_slot(slot_name)
	if save == null:
		push_warning("[GameManager] load failed for slot '%s': %s" % [
			slot_name, SaveManager.get_last_error()
		])
		return false
	current_save = save
	change_scene("res://scenes/Game.tscn")
	return true


## Load the most recently written compatible slot (F9 hotkey seam).
func load_last_slot() -> bool:
	var slot: String = SaveManager.get_last_saved_slot()
	if slot.is_empty():
		push_warning("[GameManager] no save slots available to load")
		return false
	return load_slot(slot)


## Transition to the scene at `path`. The actual change is deferred so it is
## safe to call from `_ready()` (avoids "parent node is busy" errors). Logs
## (does not crash) on failure so a missing scene surfaces as a recoverable
## error rather than a hard crash.
func change_scene(path: String) -> void:
	current_scene_path = path
	call_deferred("_do_change_scene", path)


func _do_change_scene(path: String) -> void:
	var err: int = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("GameManager: failed to load scene '%s' (error %d)" % [path, err])
