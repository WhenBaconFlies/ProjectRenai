## V2IntegrationBootstrap
##
## Headless entry scene for ticket 033's v2 end-to-end harness. The runner is
## attached to /root from a deferred callback (adding a child to /root inside
## another node's _ready() does not start its _ready() in Godot 4.2), so it
## survives every menu/Game scene swap the harness performs. PROCESS_MODE_ALWAYS
## keeps it alive while the harness pauses the live day. It prints its own
## marker; run_v2_integration_tests.ps1 reads that marker, not the exit code.
extends Node


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	var runner_script: Script = load("res://tests/V2IntegrationTest.gd") as Script
	if runner_script == null:
		push_error("[033] cannot load the v2 integration test runner script")
		get_tree().quit(1)
		return
	var runner: Node = runner_script.new()
	runner.name = "V2IntegrationRunner"
	runner.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(runner)
