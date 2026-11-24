## PauseMenuBootstrap
##
## Headless entry scene for ticket 028. The runner is attached to /root so it
## survives the GameManager scene swaps the harness exercises (Load route).
extends Node


func _ready() -> void:
	# Adding a node to /root inside _ready() does not run its own _ready() in
	# Godot 4.2; defer so the runner is fully initialised before it starts.
	call_deferred("_start")


func _start() -> void:
	var runner_script: Script = load("res://tests/PauseMenuTest.gd") as Script
	if runner_script == null:
		push_error("[028] cannot load the pause menu test runner script")
		get_tree().quit(1)
		return
	var runner: Node = runner_script.new()
	runner.name = "PauseMenuTestRunner"
	runner.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(runner)
