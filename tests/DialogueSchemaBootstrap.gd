## DialogueSchemaBootstrap
##
## Headless entry scene for ticket 021's dialogue-schema harness. Attaches the
## long-lived runner to /root so it can call ModLoader.load_mods() re-entrantly
## without being freed by a scene change. The runner prints its own marker, which
## tests/run_dialogue_schema_tests.ps1 treats as the pass/fail signal.
extends Node


func _ready() -> void:
	# Adding a node to /root from inside another node's _ready() does not run the
	# new node's own _ready() in Godot 4.2; defer the whole setup by one frame.
	call_deferred("_start")


func _start() -> void:
	var runner_script: Script = load("res://tests/DialogueSchemaTest.gd") as Script
	if runner_script == null:
		push_error("[021] cannot load the dialogue-schema test runner script")
		get_tree().quit(1)
		return
	var runner: Node = runner_script.new()
	runner.name = "DialogueSchemaRunner"
	get_tree().root.add_child(runner)
