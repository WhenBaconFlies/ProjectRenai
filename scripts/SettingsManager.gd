## SettingsManager
##
## Global singleton (autoload) that owns the player-facing settings store for
## ticket 025. Backed by a ConfigFile at `user://settings.cfg`, it holds:
##   - master volume (0..1 linear) applied through AudioManager,
##   - display resolution + fullscreen applied through DisplayServer,
##   - every ChunkConfig field applied through ChunkManager.set_config(),
##   - the current language display (English in v2), and
##   - mod enable/disable flags for the Mods Menu (ticket 031) and ModLoader
##     (ticket 029) to consume.
##
## Reads are applied on startup. Writes apply immediately where the engine allows
## (volume, chunk config); display changes raise `restart_required` so ticket
## 030's Options screen can show the notice without this autoload owning UI.
##
## A missing, unparseable, or wrong-typed config falls back to typed defaults with
## a warning — no crash and no overwrite until an explicit save. `set_config_path()`
## is a test seam that keeps harnesses off the developer's real settings file.
extends Node

## Emitted after any successful write. `key` is "audio/master_volume",
## "display", "chunk/<field>", "language", or "mods/<mod id>".
signal settings_changed(key: String)

## Emitted for settings that cannot be applied live. Ticket 030 presents the
## notice; 025 only reports it.
signal restart_required(key: String)

## --- Filesystem / sections ---------------------------------------------------

const CONFIG_PATH: String = "user://settings.cfg"
const SECTION_AUDIO: String = "audio"
const SECTION_DISPLAY: String = "display"
const SECTION_CHUNK: String = "chunk"
const SECTION_LANGUAGE: String = "language"
const SECTION_MODS: String = "mods"

## --- Defaults / authored choices --------------------------------------------

const DEFAULT_MASTER_VOLUME: float = 0.8
const DEFAULT_RESOLUTION_WIDTH: int = 1280
const DEFAULT_RESOLUTION_HEIGHT: int = 720
const DEFAULT_FULLSCREEN: bool = false
const DEFAULT_LANGUAGE: String = "English"
const MIN_RESOLUTION_DIMENSION: int = 320

## Windowed presets exposed as data for the Options screen (ticket 030).
const RESOLUTION_PRESETS: Array = [
	{"label": "1280 x 720", "width": 1280, "height": 720},
	{"label": "1366 x 768", "width": 1366, "height": 768},
	{"label": "1920 x 1080", "width": 1920, "height": 1080},
]

## Every ChunkConfig field is persisted so set_config() never resets an
## unstored field to its default. The spec names radii and tick rates; the rest
## (hysteresis, promotion, fallback size, visibility) travel with them.
const CHUNK_FIELDS: Array = [
	"close_radius_chunks", "near_radius_chunks", "hysteresis_chunks",
	"promotion_duration_sec", "close_tick_sec", "near_tick_sec",
	"far_tick_sec", "fallback_chunk_pixel_size", "hide_far_npcs",
]

## Keys that require a restart notice (the display group is emitted as "display").
const RESTART_KEYS: Array = [
	"display", "resolution_width", "resolution_height", "fullscreen",
]

## --- State ------------------------------------------------------------------

var _config: ConfigFile = ConfigFile.new()
var _config_path: String = CONFIG_PATH
var _master_volume: float = DEFAULT_MASTER_VOLUME
var _resolution_width: int = DEFAULT_RESOLUTION_WIDTH
var _resolution_height: int = DEFAULT_RESOLUTION_HEIGHT
var _fullscreen: bool = DEFAULT_FULLSCREEN
var _language: String = DEFAULT_LANGUAGE
var _chunk_config: ChunkConfig = ChunkConfig.new()
var _mods: Dictionary = {}
var _last_error: String = ""

## OS window mode observed immediately before fullscreen was enabled. On Windows
## with Godot 4.2, a direct WINDOW_MODE_WINDOWED request is dropped when the
## window entered fullscreen from MAXIMIZED, so that case restores MAXIMIZED.
var _pre_fullscreen_mode: int = DisplayServer.WINDOW_MODE_WINDOWED


func _ready() -> void:
	reload()


## --- Storage / lifecycle -----------------------------------------------------

## Path currently used for the ConfigFile (defaults to user://settings.cfg).
func get_config_path() -> String:
	return _config_path


## Redirect storage and immediately reload/apply from the new path. Used by the
## headless harness to isolate its fixture from the developer's real settings.
func set_config_path(path: String) -> void:
	if path.is_empty():
		return
	_config_path = path
	reload()


## Human-readable reason for the last load/save failure, or empty when clean.
func get_last_error() -> String:
	return _last_error


## Re-read the ConfigFile, fall back to defaults on any load/type problem, and
## apply every value to its runtime target. Safe to call at any time.
func reload() -> void:
	_config = ConfigFile.new()
	_last_error = ""
	if FileAccess.file_exists(_config_path):
		var err: int = _config.load(_config_path)
		if err != OK:
			_last_error = "ConfigFile.load() error %d" % err
			push_warning("[SettingsManager] %s for '%s'; using defaults" % [_last_error, _config_path])
			_config = ConfigFile.new()
	_load_values()
	apply_all()


## Flush the in-memory ConfigFile to disk. Returns false (with a warning) on error.
func save() -> bool:
	var err: int = _config.save(_config_path)
	if err != OK:
		_last_error = "ConfigFile.save() error %d" % err
		push_warning("[SettingsManager] %s for '%s'" % [_last_error, _config_path])
		return false
	_last_error = ""
	return true


## Re-apply every stored setting to its runtime target. Called by reload() and
## exposed for tests/observers that want a deterministic re-apply.
func apply_all() -> void:
	_apply_volume()
	_apply_display()
	_apply_chunk_config()


## True when changing `key` needs a restart notice (display settings do).
func is_restart_required(key: String) -> bool:
	return RESTART_KEYS.has(key)


## --- Audio -------------------------------------------------------------------

func get_master_volume() -> float:
	return _master_volume


## Set master volume (clamped 0..1) and apply it immediately through AudioManager.
## Returns false when the ConfigFile write failed.
func set_master_volume(value: float) -> bool:
	_master_volume = clampf(value, 0.0, 1.0)
	var saved: bool = _write(SECTION_AUDIO, "master_volume", _master_volume, "audio/master_volume")
	_apply_volume()
	return saved


## --- Display -----------------------------------------------------------------

func get_resolution_width() -> int:
	return _resolution_width


func get_resolution_height() -> int:
	return _resolution_height


func get_resolution() -> Vector2i:
	return Vector2i(_resolution_width, _resolution_height)


func get_fullscreen() -> bool:
	return _fullscreen


func get_resolution_presets() -> Array:
	return RESOLUTION_PRESETS.duplicate(true)


## Index of the active preset, or -1 for a custom resolution.
func get_resolution_preset_index() -> int:
	for i in RESOLUTION_PRESETS.size():
		var preset: Dictionary = RESOLUTION_PRESETS[i]
		if int(preset["width"]) == _resolution_width and int(preset["height"]) == _resolution_height:
			return i
	return -1


## Set a windowed size, apply it when possible, and raise the restart notice.
## Returns false when the ConfigFile write failed.
func set_resolution(width: int, height: int) -> bool:
	_resolution_width = maxi(MIN_RESOLUTION_DIMENSION, width)
	_resolution_height = maxi(MIN_RESOLUTION_DIMENSION, height)
	_config.set_value(SECTION_DISPLAY, "resolution_width", _resolution_width)
	_config.set_value(SECTION_DISPLAY, "resolution_height", _resolution_height)
	var saved: bool = save()
	settings_changed.emit("display")
	_apply_display()
	_emit_restart("display")
	return saved


## Apply a preset by index. Returns false for an out-of-range index or a failed save.
func set_resolution_preset(index: int) -> bool:
	if index < 0 or index >= RESOLUTION_PRESETS.size():
		return false
	var preset: Dictionary = RESOLUTION_PRESETS[index]
	return set_resolution(int(preset["width"]), int(preset["height"]))


## Toggle fullscreen and raise the restart notice. Returns false on a failed save.
func set_fullscreen(value: bool) -> bool:
	# Capture the live OS mode on the false -> true transition so exit can restore
	# it. Headless DisplayServer has no real window to observe.
	if value and not _fullscreen and DisplayServer.get_name() != "headless":
		_pre_fullscreen_mode = DisplayServer.window_get_mode()
	_fullscreen = value
	var saved: bool = _write(SECTION_DISPLAY, "fullscreen", _fullscreen, "display")
	_apply_display()
	_emit_restart("display")
	return saved


## --- Language ----------------------------------------------------------------

func get_language() -> String:
	return _language


func get_supported_languages() -> Array:
	return ["English"]


## Store the display language. v2 only displays English; the selector in ticket
## 030 is disabled, but this stays a typed setting for a later localization pass.
## Returns false on a failed save.
func set_language(value: String) -> bool:
	_language = value if not value.is_empty() else DEFAULT_LANGUAGE
	return _write(SECTION_LANGUAGE, "language", _language, "language")


## --- Chunk config ------------------------------------------------------------

## Copy of the authoritative ChunkConfig built from stored values.
func get_chunk_config() -> ChunkConfig:
	return _chunk_config.duplicate() as ChunkConfig


## Persist and apply a whole ChunkConfig (all CHUNK_FIELDS) at once. Returns
## false for a null config or a failed save.
func set_chunk_config(value: ChunkConfig) -> bool:
	if value == null:
		return false
	var values: Dictionary = value.to_dictionary()
	# One save for the whole config: nine individual _write() calls would hit
	# disk nine times for a single Options-screen chunk update.
	for key in CHUNK_FIELDS:
		var field: String = str(key)
		if values.has(field):
			_config.set_value(SECTION_CHUNK, field, _coerce_chunk_value(field, values[field]))
	var saved: bool = save()
	settings_changed.emit("chunk")
	_rebuild_chunk_config()
	_apply_chunk_config()
	return saved


## Read one chunk field by name. Returns null for an unknown field.
func get_chunk_value(key: String) -> Variant:
	if not CHUNK_FIELDS.has(key):
		return null
	return _chunk_config.get(key)


## Write one chunk field by name and apply the rebuilt config immediately.
## Returns false for an unknown field or a failed save.
func set_chunk_value(key: String, value: Variant) -> bool:
	if not CHUNK_FIELDS.has(key):
		push_warning("[SettingsManager] unknown chunk setting '%s'" % key)
		return false
	var saved: bool = _write(SECTION_CHUNK, key, _coerce_chunk_value(key, value), "chunk/" + key)
	_rebuild_chunk_config()
	_apply_chunk_config()
	return saved


func get_close_radius_chunks() -> int:
	return int(get_chunk_value("close_radius_chunks"))


func set_close_radius_chunks(value: int) -> bool:
	return set_chunk_value("close_radius_chunks", value)


func get_near_radius_chunks() -> int:
	return int(get_chunk_value("near_radius_chunks"))


func set_near_radius_chunks(value: int) -> bool:
	return set_chunk_value("near_radius_chunks", value)


func get_close_tick_sec() -> float:
	return float(get_chunk_value("close_tick_sec"))


func set_close_tick_sec(value: float) -> bool:
	return set_chunk_value("close_tick_sec", value)


func get_near_tick_sec() -> float:
	return float(get_chunk_value("near_tick_sec"))


func set_near_tick_sec(value: float) -> bool:
	return set_chunk_value("near_tick_sec", value)


func get_far_tick_sec() -> float:
	return float(get_chunk_value("far_tick_sec"))


func set_far_tick_sec(value: float) -> bool:
	return set_chunk_value("far_tick_sec", value)


## --- Mod flags ---------------------------------------------------------------

## A mod with no stored flag is enabled (missing config means "not disabled").
func get_mod_enabled(mod_id: String) -> bool:
	if mod_id.is_empty():
		return true
	return bool(_mods.get(mod_id, true))


## Store an enable/disable flag. ModLoader consumes it in ticket 029; 025 only
## persists and exposes it. Returns false for an empty id or a failed save.
func set_mod_enabled(mod_id: String, enabled: bool) -> bool:
	if mod_id.is_empty():
		push_warning("[SettingsManager] refusing to store a mod flag with an empty id")
		return false
	_mods[mod_id] = enabled
	return _write(SECTION_MODS, mod_id, enabled, "mods/" + mod_id)


## Copy of all stored flags (mod id -> enabled).
func get_mod_flags() -> Dictionary:
	return _mods.duplicate()


## Remove a flag entirely, returning that mod to the default (enabled) state.
## Returns false on a failed save.
func clear_mod_flag(mod_id: String) -> bool:
	# Erase the on-disk key even when _mods skipped it for a wrong-typed value;
	# otherwise a malformed flag could never be cleared through the public API.
	_mods.erase(mod_id)
	if _config.has_section(SECTION_MODS) and _config.has_section_key(SECTION_MODS, mod_id):
		_config.erase_section_key(SECTION_MODS, mod_id)
	var saved: bool = save()
	settings_changed.emit("mods/" + mod_id)
	return saved


## --- Internal: loading -------------------------------------------------------

func _load_values() -> void:
	_master_volume = _typed_float(SECTION_AUDIO, "master_volume", DEFAULT_MASTER_VOLUME, 0.0, 1.0)
	_resolution_width = _typed_int(SECTION_DISPLAY, "resolution_width", DEFAULT_RESOLUTION_WIDTH, MIN_RESOLUTION_DIMENSION)
	_resolution_height = _typed_int(SECTION_DISPLAY, "resolution_height", DEFAULT_RESOLUTION_HEIGHT, MIN_RESOLUTION_DIMENSION)
	_fullscreen = _typed_bool(SECTION_DISPLAY, "fullscreen", DEFAULT_FULLSCREEN)
	_language = _typed_string(SECTION_LANGUAGE, "language", DEFAULT_LANGUAGE)
	_mods.clear()
	if _config.has_section(SECTION_MODS):
		for key in _config.get_section_keys(SECTION_MODS):
			var id: String = str(key)
			var value: Variant = _config.get_value(SECTION_MODS, id)
			if value is bool:
				_mods[id] = value
	_rebuild_chunk_config()


func _rebuild_chunk_config() -> void:
	var fresh: ChunkConfig = ChunkConfig.new()
	for key in CHUNK_FIELDS:
		var field: String = str(key)
		fresh.set(field, _chunk_value_from_config(field))
	_chunk_config = fresh


func _chunk_value_from_config(key: String) -> Variant:
	var defaults: Dictionary = ChunkConfig.new().to_dictionary()
	if not defaults.has(key):
		return null
	if not _config.has_section(SECTION_CHUNK) or not _config.has_section_key(SECTION_CHUNK, key):
		return defaults[key]
	return _coerce_chunk_value(key, _config.get_value(SECTION_CHUNK, key), defaults[key])


func _typed_float(section: String, key: String, fallback: float, minimum: float, maximum: float) -> float:
	if not _config.has_section(section) or not _config.has_section_key(section, key):
		return fallback
	var value: Variant = _config.get_value(section, key)
	if not (value is float or value is int):
		return fallback
	return clampf(float(value), minimum, maximum)


func _typed_int(section: String, key: String, fallback: int, minimum: int) -> int:
	if not _config.has_section(section) or not _config.has_section_key(section, key):
		return fallback
	var value: Variant = _config.get_value(section, key)
	if not (value is int or value is float):
		return fallback
	return maxi(int(value), minimum)


func _typed_bool(section: String, key: String, fallback: bool) -> bool:
	if not _config.has_section(section) or not _config.has_section_key(section, key):
		return fallback
	var value: Variant = _config.get_value(section, key)
	return value if value is bool else fallback


func _typed_string(section: String, key: String, fallback: String) -> String:
	if not _config.has_section(section) or not _config.has_section_key(section, key):
		return fallback
	var value: Variant = _config.get_value(section, key)
	return value if value is String else fallback


## Coerce a stored value to the ChunkConfig field's declared type and clamp it
## to a sane range. Wrong types fall back to the field default, never crash.
func _coerce_chunk_value(key: String, value: Variant, fallback: Variant = null) -> Variant:
	var baseline: Variant = fallback
	if baseline == null:
		baseline = ChunkConfig.new().to_dictionary().get(key)
	if baseline is bool:
		if value is bool:
			return value
		if value is int:
			return value != 0
		return baseline
	if baseline is int:
		var number: int = baseline
		if value is int:
			number = value
		elif value is float:
			number = int(value)
		else:
			return baseline
		match key:
			"close_radius_chunks", "near_radius_chunks", "hysteresis_chunks":
				return maxi(0, number)
			"fallback_chunk_pixel_size":
				return maxi(1, number)
		return number
	if baseline is float:
		var number: float = baseline
		if value is float:
			number = value
		elif value is int:
			number = float(value)
		else:
			return baseline
		if key == "promotion_duration_sec" or key.ends_with("_tick_sec"):
			return maxf(0.0, number)
		return number
	return value


## --- Internal: writing / applying --------------------------------------------

func _write(section: String, key: String, value: Variant, signal_key: String) -> bool:
	_config.set_value(section, key, value)
	var saved: bool = save()
	settings_changed.emit(signal_key)
	return saved


func _emit_restart(key: String) -> void:
	if is_restart_required(key):
		restart_required.emit(key)


func _apply_volume() -> void:
	if AudioManager != null and AudioManager.has_method("set_master_volume"):
		AudioManager.set_master_volume(_master_volume)


## Window mode requested when fullscreen is off (pure seam for headless tests).
func get_window_mode_for_restore() -> int:
	if _pre_fullscreen_mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		return DisplayServer.WINDOW_MODE_MAXIMIZED
	return DisplayServer.WINDOW_MODE_WINDOWED


## Headless test seam for the restore-mode decision; production captures the
## live window mode in set_fullscreen(true) instead.
func set_pre_fullscreen_mode(mode: int) -> void:
	_pre_fullscreen_mode = mode


func _apply_display() -> void:
	# Headless DisplayServer has no window; storage still round-trips for tests.
	if DisplayServer.get_name() == "headless":
		return
	var mode: int = DisplayServer.WINDOW_MODE_FULLSCREEN if _fullscreen else get_window_mode_for_restore()
	DisplayServer.window_set_mode(mode)
	if not _fullscreen:
		if mode == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_size(Vector2i(_resolution_width, _resolution_height))
		_pre_fullscreen_mode = DisplayServer.WINDOW_MODE_WINDOWED


func _apply_chunk_config() -> void:
	if ChunkManager != null and ChunkManager.has_method("set_config"):
		ChunkManager.set_config(_chunk_config)
