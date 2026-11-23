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
	change_scene("res://scenes/Game.tscn")


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
