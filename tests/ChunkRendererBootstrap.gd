## ChunkRendererBootstrap
##
## Headless entry scene for ticket 020's chunk-renderer harness. Attaches the
## long-lived runner to /root (it survives the DebugStart -> Game scene change),
## deferred from _ready() so Godot 4.2 actually runs the runner's own _ready().
extends Node


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	var runner_script: Script = load("res://tests/ChunkRendererTest.gd") as Script
	if runner_script == null:
		push_error("[020] cannot load the chunk renderer test runner script")
		get_tree().quit(1)
		return
	var runner: Node = runner_script.new()
	runner.name = "ChunkRendererRunner"
	get_tree().root.add_child(runner)
