## LoadGameBootstrap
##
## Headless entry scene for ticket 027. Attaches the long-lived runner to /root
## (so it survives GameManager's scene swaps) and lets it drive the real Load
## Game screen. The runner, not this bootstrap, owns all assertions.
extends Node


func _ready() -> void:
	# Adding a node to /root inside _ready() does not run its own _ready() in
	# Godot 4.2; defer so the runner is fully initialised before it starts.
	call_deferred("_start")


func _start() -> void:
	var runner_script: Script = load("res://tests/LoadGameTest.gd") as Script
	if runner_script == null:
		push_error("[027] cannot load the Load Game test runner script")
		get_tree().quit(1)
		return
	var runner: Node = runner_script.new()
	runner.name = "LoadGameTestRunner"
	get_tree().root.add_child(runner)
