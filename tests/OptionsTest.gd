## OptionsTest
##
## Persistent headless acceptance harness for ticket 030. Boots the real
## Options scene, drives its controls at their public seams and asserts external
## behaviour only: initial values come from SettingsManager, volume/chunk writes
## apply immediately, resolution/fullscreen writes apply immediately (no restart
## notice is shown), English is shown in a disabled selector, no
## relationship-feedback toggle exists, values persist through reload, and both
## Back routes work (injected + default Main Menu). Config writes go to a
## dedicated user:// fixture so the developer's real settings.cfg is untouched.
## Prints ALL_030_CHECKS_PASSED only when every assertion passed.
extends Node

const TEST_CONFIG_PATH: String = "user://options_test.cfg"
const OPTIONS_SCENE: String = "res://scenes/Options.tscn"
const EXPECTED_CHECKS: int = 23

var _passed: int = 0
var _failed: int = 0
var _restarts: Array[String] = []
var _volume_writes: int = 0
var _back_calls: int = 0
var _options: Control = null


func _ready() -> void:
	call_deferred("_run")


func _on_restart_required(key: String) -> void:
	_restarts.append(key)


func _on_settings_changed(key: String) -> void:
	if key == "audio/master_volume":
		_volume_writes += 1


func _record_back() -> void:
	_back_calls += 1


func _run() -> void:
	_remove_fixture()
	SettingsManager.set_config_path(TEST_CONFIG_PATH)
	# Seed stored values first so the screen must populate from SettingsManager
	# rather than from defaults; these writes happen before the signal is hooked.
	SettingsManager.set_master_volume(0.5)
	SettingsManager.set_resolution_preset(1)
	SettingsManager.set_fullscreen(false)
	SettingsManager.restart_required.connect(_on_restart_required)
	SettingsManager.settings_changed.connect(_on_settings_changed)
	_restarts.clear()

	var packed := load(OPTIONS_SCENE) as PackedScene
	_check(packed != null, "T1a: Options.tscn loads")
	if packed == null:
		_finish()
		return
	_options = packed.instantiate() as Control
	get_tree().root.add_child(_options)
	await _settle()

	var script: Script = _options.get_script() as Script
	_check(script != null and script.resource_path == "res://scripts/Options.gd",
		"T1: Options uses the real Options script, not the placeholder")
	var title := _node("TitleLabel") as Label
	_check(title != null and title.text == "Options", "T2: title label reads Options")

	var expected_nodes: Array = [
		"SettingsScroll/SettingsBox/VolumeRow/VolumeSlider",
		"SettingsScroll/SettingsBox/VolumeRow/VolumeValueLabel",
		"SettingsScroll/SettingsBox/CloseRadiusRow/CloseRadiusSpin",
		"SettingsScroll/SettingsBox/NearRadiusRow/NearRadiusSpin",
		"SettingsScroll/SettingsBox/CloseTickRow/CloseTickSpin",
		"SettingsScroll/SettingsBox/NearTickRow/NearTickSpin",
		"SettingsScroll/SettingsBox/FarTickRow/FarTickSpin",
		"SettingsScroll/SettingsBox/ResolutionRow/ResolutionOption",
		"SettingsScroll/SettingsBox/FullscreenRow/FullscreenCheck",
		"SettingsScroll/SettingsBox/LanguageRow/LanguageOption",
		"BackButton",
	]
	var structure_ok: bool = true
	for path in expected_nodes:
		if _node(path) == null:
			structure_ok = false
	_check(structure_ok, "T3: every expected control exists at its stable path")

	# --- Volume: populated, immediate, no restart -----------------------------
	var volume_slider := _node("SettingsScroll/SettingsBox/VolumeRow/VolumeSlider") as HSlider
	var volume_label := _node("SettingsScroll/SettingsBox/VolumeRow/VolumeValueLabel") as Label
	_check(volume_slider != null and is_equal_approx(volume_slider.value, 50.0)
		and volume_label != null and volume_label.text == "50%",
		"T4: volume slider/label populate from the stored 0.5 value")
	if volume_slider != null:
		# A multi-step drag must not write settings until the drag is committed.
		volume_slider.value = 20.0
		volume_slider.value = 30.0
		volume_slider.value = 37.0
	_check(_volume_writes == 0 and is_equal_approx(SettingsManager.get_master_volume(), 0.5)
		and volume_label != null and volume_label.text == "37%",
		"T5a: intermediate drag steps update the readout without writing settings")
	if volume_slider != null:
		volume_slider.drag_ended.emit(true)
	_check(_volume_writes == 1
		and is_equal_approx(SettingsManager.get_master_volume(), 0.37)
		and is_equal_approx(AudioManager.get_master_volume(), 0.37),
		"T5b: drag commit writes once and applies to SettingsManager and AudioManager")

	# --- Chunk radii / tick rates: immediate, no restart ----------------------
	var close_radius := _node("SettingsScroll/SettingsBox/CloseRadiusRow/CloseRadiusSpin") as SpinBox
	var near_radius := _node("SettingsScroll/SettingsBox/NearRadiusRow/NearRadiusSpin") as SpinBox
	var close_tick := _node("SettingsScroll/SettingsBox/CloseTickRow/CloseTickSpin") as SpinBox
	var near_tick := _node("SettingsScroll/SettingsBox/NearTickRow/NearTickSpin") as SpinBox
	var far_tick := _node("SettingsScroll/SettingsBox/FarTickRow/FarTickSpin") as SpinBox
	_check(close_radius != null and near_radius != null and close_tick != null
		and near_tick != null and far_tick != null
		and is_equal_approx(close_radius.value, float(SettingsManager.get_close_radius_chunks()))
		and is_equal_approx(close_tick.value, SettingsManager.get_close_tick_sec()),
		"T6: chunk controls populate from SettingsManager")
	if close_radius != null:
		close_radius.value = 4.0
		near_radius.value = 7.0
		close_tick.value = 0.25
		near_tick.value = 0.6
		far_tick.value = 9.0
	var live_chunk: ChunkConfig = ChunkManager.get_config()
	_check(SettingsManager.get_close_radius_chunks() == 4
		and SettingsManager.get_near_radius_chunks() == 7
		and is_equal_approx(SettingsManager.get_close_tick_sec(), 0.25)
		and is_equal_approx(SettingsManager.get_near_tick_sec(), 0.6)
		and is_equal_approx(SettingsManager.get_far_tick_sec(), 9.0)
		and live_chunk.close_radius_chunks == 4
		and is_equal_approx(live_chunk.close_tick_sec, 0.25)
		and is_equal_approx(live_chunk.far_tick_sec, 9.0),
		"T7: chunk radius/rate changes apply immediately to SettingsManager and ChunkManager")
	# Raising close past near must clamp near up to the effective runtime value.
	close_radius.value = 10.0
	_check(SettingsManager.get_close_radius_chunks() == 10
		and SettingsManager.get_near_radius_chunks() == 10
		and is_equal_approx(near_radius.value, 10.0)
		and is_equal_approx(near_radius.min_value, 10.0),
		"T7b: raising close radius clamps near to the effective value")
	_check(_restarts.is_empty(),
		"T8: volume/chunk writes raise no restart signal")

	# --- Resolution / fullscreen: presets + restart notice --------------------
	var resolution_option := _node("SettingsScroll/SettingsBox/ResolutionRow/ResolutionOption") as OptionButton
	_check(resolution_option != null and resolution_option.item_count == 3
		and resolution_option.get_item_text(0) == "1280 x 720"
		and resolution_option.get_item_text(1) == "1366 x 768"
		and resolution_option.get_item_text(2) == "1920 x 1080"
		and resolution_option.selected == 1,
		"T9: resolution presets are populated and the stored preset is selected")
	if resolution_option != null:
		resolution_option.select(2)
		resolution_option.item_selected.emit(2)
	_check(SettingsManager.get_resolution() == Vector2i(1920, 1080)
		and _restarts.has("display") and _node("RestartNotice") == null,
		"T10: a preset applies immediately through SettingsManager with no notice UI")
	var fullscreen_check := _node("SettingsScroll/SettingsBox/FullscreenRow/FullscreenCheck") as CheckButton
	if fullscreen_check != null:
		fullscreen_check.button_pressed = true
	_check(SettingsManager.get_fullscreen() and _restarts.size() >= 2,
		"T11: fullscreen applies immediately through SettingsManager")
	if fullscreen_check != null:
		fullscreen_check.button_pressed = false
	_check(not SettingsManager.get_fullscreen(),
		"T11b: toggling fullscreen off restores the stored windowed state")
	# Windows/Godot drops a direct WINDOWED request when fullscreen was entered
	# from MAXIMIZED; the restore-mode decision is pure and testable headlessly.
	SettingsManager.set_pre_fullscreen_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	var maximized_restore: int = SettingsManager.get_window_mode_for_restore()
	SettingsManager.set_pre_fullscreen_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_check(maximized_restore == DisplayServer.WINDOW_MODE_MAXIMIZED
		and SettingsManager.get_window_mode_for_restore() == DisplayServer.WINDOW_MODE_WINDOWED,
		"T11c: leaving fullscreen restores MAXIMIZED when entered from it, else WINDOWED")
	# Restore the ON state so the persistence check below still verifies fullscreen.
	if fullscreen_check != null:
		fullscreen_check.button_pressed = true

	# --- Language display -----------------------------------------------------
	var language_option := _node("SettingsScroll/SettingsBox/LanguageRow/LanguageOption") as OptionButton
	_check(language_option != null and language_option.item_count == 1
		and language_option.get_item_text(0) == "English"
		and language_option.selected == 0 and language_option.disabled,
		"T12: English is shown as current in a disabled selector")

	# --- Relationship-feedback toggle is deliberately absent -----------------
	var all_nodes: Array = []
	_collect_nodes(_options, all_nodes)
	var feedback_found: bool = false
	var toggle_count: int = 0
	for node in all_nodes:
		var n: Node = node
		if n.name.to_lower().contains("feedback"):
			feedback_found = true
		if n is CheckButton or n is CheckBox:
			toggle_count += 1
		if n is Label and (n as Label).text.to_lower().contains("feedback"):
			feedback_found = true
	_check(not feedback_found and toggle_count == 1,
		"T13: no relationship-feedback toggle; fullscreen is the only check control")

	# --- Persistence ----------------------------------------------------------
	SettingsManager.reload()
	_check(is_equal_approx(SettingsManager.get_master_volume(), 0.37)
		and SettingsManager.get_close_radius_chunks() == 10
		and SettingsManager.get_near_radius_chunks() == 10
		and is_equal_approx(SettingsManager.get_close_tick_sec(), 0.25)
		and SettingsManager.get_resolution() == Vector2i(1920, 1080)
		and SettingsManager.get_fullscreen()
		and is_equal_approx(AudioManager.get_master_volume(), 0.37)
		and ChunkManager.get_config().close_radius_chunks == 10,
		"T14: all UI changes persist and re-apply after SettingsManager.reload()")

	# --- Back seam (injected action + default route) --------------------------
	var back_button := _node("BackButton") as Button
	_check(_options.has_method("set_back_action") and back_button != null,
		"T15: Back seam exists for the pause overlay's in-place embedding")
	_options.set_back_action(Callable(self, "_record_back"))
	if back_button != null:
		back_button.pressed.emit()
	_check(_back_calls == 1, "T16: an injected Back action is called exactly once")
	_options.set_back_action(Callable())
	var swaps_before: int = GameManager.scene_change_count
	if back_button != null:
		back_button.pressed.emit()
	await _settle()
	var current := get_tree().current_scene
	_check(_options.back_action.is_valid()
		and GameManager.scene_change_count == swaps_before + 1
		and current != null and current.name == "MainMenu",
		"T17: an invalid Back action restores the Main Menu route")

	_check(_passed == EXPECTED_CHECKS - 1, "T18: all expected 030 checks executed")
	_cleanup()
	_finish()


## --- Helpers -----------------------------------------------------------------

func _node(path: String) -> Node:
	return _options.get_node_or_null(path) if _options != null else null


func _collect_nodes(node: Node, result: Array) -> void:
	result.append(node)
	for child in node.get_children():
		_collect_nodes(child, result)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _remove_fixture() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CONFIG_PATH))


func _cleanup() -> void:
	_remove_fixture()
	SettingsManager.set_config_path(SettingsManager.CONFIG_PATH)


## --- Assertion / completion -------------------------------------------------

func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("[030] PASS " + label)
	else:
		_failed += 1
		print("[030] FAIL " + label)


func _finish() -> void:
	print("[030] RESULT passed=%d failed=%d" % [_passed, _failed])
	if _failed == 0:
		print("ALL_030_CHECKS_PASSED")
	else:
		print("SOME_030_CHECKS_FAILED")
	get_tree().quit(0 if _failed == 0 else 1)
