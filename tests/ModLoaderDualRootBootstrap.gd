## ModLoaderDualRootBootstrap
##
## Headless entry scene for ticket 029's ModLoader harness. The runner is
## attached to /root on a deferred call, matching the 021/025 bootstrap pattern,
## so every autoload (including SettingsManager) is fully initialised before the
## harness redirects settings storage and drives ModLoader re-entrantly.
extends Node


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	var runner_script: Script = load("res://tests/ModLoaderDualRootTest.gd") as Script
	if runner_script == null:
		push_error("[029] cannot load the dual-root test runner script")
		get_tree().quit(1)
		return
	var runner: Node = runner_script.new()
	runner.name = "ModLoaderDualRootRunner"
	get_tree().root.add_child(runner)
