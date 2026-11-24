## IntegrationBootstrap
##
## Headless entry scene for ticket 018's day-loop acceptance harness. It does two
## small jobs: attach the long-lived runner to the scene-tree root, then hand
## control to the REAL game entry point (DebugStart.tscn) through GameManager.
##
## The runner is parented to /root rather than left in this scene because Godot
## frees the current scene on change_scene_to_file(). A child of /root survives
## that swap and can observe the DebugStart -> GameManager -> Game.tscn path
## exactly as a player launch does.
extends Node


func _ready() -> void:
	# Adding a node to /root from inside another node's _ready() does not run the
	# new node's own _ready() in Godot 4.2. Deferring the whole setup to the idle
	# frame guarantees the runner is fully initialised before the scene changes.
	call_deferred("_start")


func _start() -> void:
	var runner_script: Script = load("res://tests/DayLoopIntegrationTest.gd") as Script
	if runner_script == null:
		push_error("[018] cannot load the integration test runner script")
		get_tree().quit(1)
		return
	var runner: Node = runner_script.new()
	runner.name = "DayLoopIntegrationRunner"
	get_tree().root.add_child(runner)

	# Runner._ready() queues its coroutine first, so it installs its listeners
	# before GameManager performs the (also deferred) scene change below.
	GameManager.change_scene("res://scenes/DebugStart.tscn")
