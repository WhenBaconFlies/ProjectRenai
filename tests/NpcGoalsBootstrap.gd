## NpcGoalsBootstrap
##
## Headless entry scene for ticket 032's relationship-goal harness. The runner is
## parented to /root from a deferred call so autoloads and the global class cache
## are ready before NpcAi is exercised.
extends Node


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	var runner_script: Script = load("res://tests/NpcGoalsTest.gd") as Script
	if runner_script == null:
		push_error("[032] cannot load the npc-goals test runner script")
		get_tree().quit(1)
		return
	var runner: Node = runner_script.new()
	runner.name = "NpcGoalsRunner"
	get_tree().root.add_child(runner)
