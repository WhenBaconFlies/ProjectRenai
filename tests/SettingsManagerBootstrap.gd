## SettingsManagerBootstrap
##
## Headless entry scene for ticket 025's settings harness. The runner is attached
## to /root on a deferred call, matching the 021/022 bootstrap pattern, so all
## autoloads (including SettingsManager) are fully initialised before checks run.
extends Node


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	var runner_script: Script = load("res://tests/SettingsManagerTest.gd") as Script
	if runner_script == null:
		push_error("[025] cannot load the settings test runner script")
		get_tree().quit(1)
		return
	var runner: Node = runner_script.new()
	runner.name = "SettingsManagerRunner"
	get_tree().root.add_child(runner)
