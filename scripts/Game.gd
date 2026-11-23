## Game
##
## Root controller for the playable Game scene. The day clock starts here, in
## this scene's _ready(), so any scene-level listener is connected before
## TimeManager emits day_started / state_changed for day 1.
extends Node2D


func _ready() -> void:
	# A fresh start has no save to restore. A loaded save (ticket 017) is
	# restored by that ticket instead, so never overwrite a running clock.
	if not TimeManager.is_running() and GameManager.current_save == null:
		TimeManager.start_day(1)
