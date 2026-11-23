## GameManager
##
## Global singleton holding overall game state: the currently loaded save,
## scene-transition requests, and the "fresh start / no save" path exercised
## by DebugStart. Behaviour is filled in by later tickets (day loop, scenes);
## this is the stable entry point other systems talk to.
extends Node


func _ready() -> void:
	# Autoload initialized. No state to restore yet (fresh start is the default).
	pass
