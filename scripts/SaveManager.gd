## SaveManager
##
## Global singleton responsible for save/load, slot management, and
## instance<->template linkage by stable template IDs. Stub for now;
## behaviour lands in the save-load ticket.
extends Node


func _ready() -> void:
	pass


## Log-only autosave hook called by TimeManager when the day ends. Ticket 017
## replaces this with a real Godot Resource save; keeping the seam here avoids
## duplicating save logic in the day-state-machine ticket.
func autosave(snapshot: Dictionary = {}) -> void:
	# `snapshot` is the TimeManager.get_day_snapshot() payload; ticket 017
	# serializes it into a Godot Resource save.
	print("[SaveManager] autosave requested (stub; real save lands in ticket 017)")
