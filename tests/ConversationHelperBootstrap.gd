## ConversationHelperBootstrap
##
## Headless entry scene for ticket 023's conversation-helper harness. Attaches the
## long-lived runner to /root so helper instances and registry reads are stable.
## The runner prints its own marker, which
## tests/run_conversation_helper_tests.ps1 treats as the pass/fail signal.
extends Node


func _ready() -> void:
	# Adding a node to /root from inside another node's _ready() does not run the
	# new node's own _ready() in Godot 4.2; defer the whole setup by one frame.
	call_deferred("_start")


func _start() -> void:
	var runner_script: Script = load("res://tests/ConversationHelperTest.gd") as Script
	if runner_script == null:
		push_error("[023] cannot load the conversation-helper test runner script")
		get_tree().quit(1)
		return
	var runner: Node = runner_script.new()
	runner.name = "ConversationHelperRunner"
	get_tree().root.add_child(runner)
