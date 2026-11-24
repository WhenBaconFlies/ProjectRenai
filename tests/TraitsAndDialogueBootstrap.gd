## TraitsAndDialogueBootstrap
##
## Headless entry scene for ticket 022's content harness. The runner is attached
## to /root on a deferred call, matching the 021 bootstrap pattern, so autoloads
## (ModLoader, TimeManager) are fully initialised before any check runs.
extends Node


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	var runner_script: Script = load("res://tests/TraitsAndDialogueContentTest.gd") as Script
	if runner_script == null:
		push_error("[022] cannot load the content test runner script")
		get_tree().quit(1)
		return
	var runner: Node = runner_script.new()
	runner.name = "TraitsAndDialogueRunner"
	get_tree().root.add_child(runner)
