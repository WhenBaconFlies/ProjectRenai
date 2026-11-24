## SettingsManagerTest
##
## Persistent headless acceptance harness for ticket 025. It exercises the real
## autoload at its public seams only: defaults on a missing file, immediate
## application to AudioManager / ChunkManager, restart-notice reporting, full
## save/reload round-trip of every setting, mod flag add/clear, wrong-typed value
## fallback, and corrupt-config fallback. The fixture lives at a dedicated
## user:// path so the developer's real settings.cfg is never touched.
## Prints ALL_025_CHECKS_PASSED only when every assertion passed.
extends Node

const TEST_CONFIG_PATH: String = "user://settings_manager_test.cfg"
const EXPECTED_CHECKS: int = 21

var _passed: int = 0
var _failed: int = 0
var _changed: Array[String] = []
var _restarts: Array[String] = []


func _ready() -> void:
	SettingsManager.settings_changed.connect(_on_settings_changed)
	SettingsManager.restart_required.connect(_on_restart_required)
	call_deferred("_run")


func _on_settings_changed(key: String) -> void:
	_changed.append(key)


func _on_restart_required(key: String) -> void:
	_restarts.append(key)


func _run() -> void:
	_remove_fixture()
	SettingsManager.set_config_path(TEST_CONFIG_PATH)

	# --- Defaults on a missing config -----------------------------------------
	_check(SettingsManager.get_config_path() == TEST_CONFIG_PATH,
		"T1: config path seam redirects storage to the test fixture")
	_check(
		SettingsManager.get_master_volume() == SettingsManager.DEFAULT_MASTER_VOLUME
		and SettingsManager.get_resolution() == Vector2i(SettingsManager.DEFAULT_RESOLUTION_WIDTH, SettingsManager.DEFAULT_RESOLUTION_HEIGHT)
		and not SettingsManager.get_fullscreen()
		and SettingsManager.get_language() == SettingsManager.DEFAULT_LANGUAGE,
		"T2: missing config falls back to audio/display/language defaults"
	)
	_check(_dicts_equal(SettingsManager.get_chunk_config().to_dictionary(), ChunkConfig.new().to_dictionary()),
		"T3: missing config falls back to every ChunkConfig default")
	_check(SettingsManager.get_mod_enabled("mod:absent"),
		"T4: a mod with no stored flag is enabled")

	# --- Immediate application -------------------------------------------------
	SettingsManager.set_master_volume(0.37)
	_check(is_equal_approx(AudioManager.get_master_volume(), 0.37),
		"T5: volume write applies to AudioManager immediately")

	SettingsManager.set_close_radius_chunks(3)
	_check(ChunkManager.get_config().close_radius_chunks == 3,
		"T6: chunk write applies to ChunkManager immediately")

	_check(_restarts.is_empty(),
		"T7: volume/chunk writes need no restart notice")

	_check(SettingsManager.get_resolution_presets().size() == 3
		and SettingsManager.set_resolution_preset(2)
		and SettingsManager.get_resolution() == Vector2i(1920, 1080),
		"T8: authored resolution presets are selectable")

	# The preset in T8 also reports a restart; clear it so T9 measures only the
	# two explicit display writes below.
	_restarts.clear()
	SettingsManager.set_resolution(1600, 900)
	SettingsManager.set_fullscreen(true)
	_check(_restarts == ["display", "display"],
		"T9: resolution/fullscreen writes raise the restart notice")

	# --- Full round-trip -------------------------------------------------------
	SettingsManager.set_master_volume(0.62)
	SettingsManager.set_language("TestLanguage")
	SettingsManager.set_mod_enabled("mod:fixture", false)
	var custom: ChunkConfig = ChunkConfig.new()
	custom.close_radius_chunks = 3
	custom.near_radius_chunks = 6
	custom.hysteresis_chunks = 2
	custom.promotion_duration_sec = 0.75
	custom.close_tick_sec = 0.05
	custom.near_tick_sec = 0.4
	custom.far_tick_sec = 7.5
	custom.fallback_chunk_pixel_size = 256
	custom.hide_far_npcs = false
	SettingsManager.set_chunk_config(custom)

	var expected_chunk: Dictionary = custom.to_dictionary()
	_check(SettingsManager.save(), "T10a: explicit save succeeds")
	SettingsManager.reload()
	_check(
		is_equal_approx(SettingsManager.get_master_volume(), 0.62)
		and SettingsManager.get_resolution() == Vector2i(1600, 900)
		and SettingsManager.get_fullscreen()
		and SettingsManager.get_language() == "TestLanguage"
		and not SettingsManager.get_mod_enabled("mod:fixture"),
		"T10: audio/display/language/mod settings round-trip through save/reload"
	)
	# Startup application is a separate contract from storage: these would stay
	# green even if reload() stopped calling apply_all().
	_check(is_equal_approx(AudioManager.get_master_volume(), 0.62),
		"T10b: reload re-applies restored volume to AudioManager")
	_check(_dicts_equal(ChunkManager.get_config().to_dictionary(), expected_chunk),
		"T10c: reload re-applies restored chunk config to ChunkManager")
	_check(SettingsManager.is_restart_required("display")
		and SettingsManager.is_restart_required("fullscreen")
		and not SettingsManager.is_restart_required("audio/master_volume"),
		"T10d: display keys still report restart-required after reload")
	_check(_dicts_equal(SettingsManager.get_chunk_config().to_dictionary(), expected_chunk),
		"T11: every ChunkConfig field round-trips through save/reload")
	_check(_changed.has("audio/master_volume") and _changed.has("chunk/close_radius_chunks")
		and _changed.has("display") and _changed.has("language") and _changed.has("mods/mod:fixture"),
		"T12: every write emits settings_changed with its key")

	SettingsManager.clear_mod_flag("mod:fixture")
	_check(SettingsManager.get_mod_enabled("mod:fixture")
		and not SettingsManager.get_mod_flags().has("mod:fixture"),
		"T13: clearing a mod flag returns it to the enabled default")

	# --- Robustness ------------------------------------------------------------
	_write_bad_types()
	SettingsManager.reload()
	_check(
		SettingsManager.get_master_volume() == SettingsManager.DEFAULT_MASTER_VOLUME
		and SettingsManager.get_resolution_width() == SettingsManager.DEFAULT_RESOLUTION_WIDTH
		and SettingsManager.get_language() == SettingsManager.DEFAULT_LANGUAGE
		and SettingsManager.get_close_radius_chunks() == ChunkConfig.new().close_radius_chunks
		and SettingsManager.get_fullscreen(),
		"T14: wrong-typed values fall back while valid ones survive"
	)

	SettingsManager.clear_mod_flag("mod:bad")
	var disk_config: ConfigFile = ConfigFile.new()
	var read_err: int = disk_config.load(TEST_CONFIG_PATH)
	_check(read_err == OK and not disk_config.has_section_key("mods", "mod:bad"),
		"T14b: clearing a wrong-typed mod flag removes the disk key")

	_write_garbage()
	SettingsManager.reload()
	_check(
		not SettingsManager.get_last_error().is_empty()
		and SettingsManager.get_master_volume() == SettingsManager.DEFAULT_MASTER_VOLUME
		and SettingsManager.get_language() == SettingsManager.DEFAULT_LANGUAGE,
		"T15: corrupt config falls back to defaults without crashing"
	)

	_check(_passed == EXPECTED_CHECKS - 1,
		"T16: all expected 025 checks executed")
	_cleanup()
	_finish()


## --- Fixture helpers ---------------------------------------------------------

func _remove_fixture() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CONFIG_PATH))


func _write_bad_types() -> void:
	var file: ConfigFile = ConfigFile.new()
	file.set_value("audio", "master_volume", "loud")
	file.set_value("display", "resolution_width", "wide")
	file.set_value("display", "fullscreen", true)
	file.set_value("language", "language", 7)
	file.set_value("chunk", "close_radius_chunks", "two")
	file.set_value("mods", "mod:bad", "not-a-bool")
	var err: int = file.save(TEST_CONFIG_PATH)
	if err != OK:
		print("[025] FAIL: could not write wrong-typed fixture (error %d)" % err)


func _write_garbage() -> void:
	var file: FileAccess = FileAccess.open(TEST_CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		print("[025] FAIL: could not open corrupt fixture for writing")
		return
	file.store_string("[audio\nmaster_volume = 0.1\n")
	file.close()


func _cleanup() -> void:
	_remove_fixture()
	SettingsManager.set_config_path(SettingsManager.CONFIG_PATH)


func _dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in b.keys():
		if not a.has(key):
			return false
		var left: Variant = a[key]
		var right: Variant = b[key]
		if left is float or right is float:
			if not is_equal_approx(float(left), float(right)):
				return false
		elif left != right:
			return false
	return true


## --- Assertion / completion -------------------------------------------------

func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("[025] PASS " + label)
	else:
		_failed += 1
		print("[025] FAIL " + label)


func _finish() -> void:
	print("[025] RESULT passed=%d failed=%d" % [_passed, _failed])
	if _failed == 0:
		print("ALL_025_CHECKS_PASSED")
	else:
		print("SOME_025_CHECKS_FAILED")
	get_tree().quit(0 if _failed == 0 else 1)
