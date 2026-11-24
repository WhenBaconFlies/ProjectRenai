## OptionsBootstrap
##
## Headless entry scene for ticket 030. The runner is attached to /root so it
## survives the Main Menu scene swap exercised by the Back-route check.
extends Node


func _ready() -> void:
	# Adding a node to /root inside _ready() does not run its own _ready() in
	# Godot 4.2; defer so the runner is fully initialised before it starts.
	call_deferred("_start")


func _start() -> void:
	var runner_script: Script = load("res://tests/OptionsTest.gd") as Script
	if runner_script == null:
		push_error("[030] cannot load the options test runner script")
		get_tree().quit(1)
		return
	var runner: Node = runner_script.new()
	runner.name = "OptionsTestRunner"
	runner.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(runner)
