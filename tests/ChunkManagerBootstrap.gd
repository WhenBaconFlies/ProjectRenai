## ChunkManagerBootstrap
##
## Headless entry scene for ticket 019's tiered-simulation harness. Attaches the
## long-lived runner to /root (it survives the DebugStart -> Game scene change),
## deferred from _ready() so Godot 4.2 actually runs the runner's own _ready().
## The runner prints ALL_019_CHECKS_PASSED only when every assertion passes.
extends Node


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	var runner_script: Script = load("res://tests/ChunkManagerTest.gd") as Script
	if runner_script == null:
		push_error("[019] cannot load the ChunkManager test runner script")
		get_tree().quit(1)
		return
	var runner: Node = runner_script.new()
	runner.name = "ChunkManagerRunner"
	get_tree().root.add_child(runner)
