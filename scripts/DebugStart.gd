## DebugStart
##
## Minimal debug launcher scene script. Auto-starts a default day by asking
## GameManager to enter the fresh-start (no save) path, which loads
## Game.tscn. No menu flow is required to reach gameplay.
extends Node


func _ready() -> void:
	# Delegate to GameManager so the fresh-start / no-save path is exercised
	# through the autoload rather than ad-hoc scene switching here.
	GameManager.start_fresh_day()
