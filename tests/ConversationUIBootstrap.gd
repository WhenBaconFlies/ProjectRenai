## ConversationUIBootstrap
##
## Headless entry scene for ticket 024's conversation-overlay harness. Attaches
## the long-lived runner to /root so scene changes and node lifetime cannot free
## it; the runner prints its own marker, which the PowerShell launcher reads.
extends Node


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	var runner_script: Script = load("res://tests/ConversationUITest.gd") as Script
	if runner_script == null:
		push_error("[024] cannot load the conversation UI test runner script")
		get_tree().quit(1)
		return
	var runner: Node = runner_script.new()
	runner.name = "ConversationUIRunner"
	get_tree().root.add_child(runner)
