## ModsMenuTest
##
## Persistent headless acceptance harness for ticket 031. Boots the real ModsMenu
## scene and asserts external behaviour only: both scan roots are listed with
## manifest metadata and load status, toggles write/remove settings flags, a
## restart notice appears without a live rescan, flags apply on the next launch
## (including dependency satisfaction), invalid mods show their diagnostic, and
## both Back routes work. Config writes go to a fixture so the developer's real
## settings.cfg is untouched. Prints ALL_031_CHECKS_PASSED when every check passes.
extends Node

const ROOT_A: String = "user://mods031_root_a/"
const ROOT_B: String = "user://mods031_root_b/"
const SETTINGS_PATH: String = "user://mods031_settings.cfg"
const MODS_SCENE: String = "res://scenes/ModsMenu.tscn"
const EXPECTED_CHECKS: int = 24

var _passed: int = 0
var _failed: int = 0
var _executed: int = 0
var _back_calls: int = 0
var _menu: Control = null
var _snapshot: Array = []


func _ready() -> void:
	call_deferred("_run")


func _record_back() -> void:
	_back_calls += 1


func _run() -> void:
	# RED guard: against the pre-031 build this fails as a normal assertion
	# instead of aborting on a missing-method runtime error.
	if not ModLoader.has_method("get_installed_mods"):
		_check(false, "T0: ModLoader exposes the get_installed_mods() snapshot API")
		_finish()
		return
	_check(true, "T0: ModLoader exposes the get_installed_mods() snapshot API")

	_remove_file(SETTINGS_PATH)
	_remove_dir_recursive(ROOT_A)
	_remove_dir_recursive(ROOT_B)
	SettingsManager.set_config_path(SETTINGS_PATH)
	# Seed the player-disabled flag before the screen is instantiated.
	SettingsManager.set_mod_enabled("menu:disabled", false)

	_make_fixtures()
	ModLoader.load_mods_from_roots([ROOT_A, ROOT_B])
	_snapshot = ModLoader.get_installed_mods()

	# --- Loader snapshot: metadata, status and diagnostics from both roots ----
	_check(_snapshot.size() == 6 and _entry("menu:base") != null
		and _entry("menu:user") != null and _entry("bad_manifest") != null
		and _entry("no_manifest") != null,
		"T1: all six discovered mods from both roots appear in the snapshot")
	var base: Dictionary = _entry("menu:base")
	var user: Dictionary = _entry("menu:user")
	_check(base.get("name", "") == "Base Mod" and base.get("version", "") == "1.2.3"
		and base.get("author", "") == "Tester"
		and user.get("name", "") == "User Mod" and user.get("version", "") == "0.9"
		and user.get("author", "") == "User"
		and (user.get("dependencies", []) as Array).has("menu:base"),
		"T2: name/version/author/dependencies come from manifests in both roots")
	var disabled: Dictionary = _entry("menu:disabled")
	var needs: Dictionary = _entry("menu:needs_disabled")
	var bad: Dictionary = _entry("bad_manifest")
	var no_manifest: Dictionary = _entry("no_manifest")
	_check(disabled.get("status", "") == "skipped"
		and str(disabled.get("reason", "")).contains("disabled (settings flag)")
		and needs.get("status", "") == "skipped"
		and str(needs.get("reason", "")).contains("missing dependency")
		and str(bad.get("reason", "")).contains("required field 'author'")
		and str(no_manifest.get("reason", "")).contains("missing mod.json"),
		"T3: skipped mods carry their load status and diagnostic reason")

	# --- Real scene, title and stable node names ------------------------------
	var packed := load(MODS_SCENE) as PackedScene
	_check(packed != null, "T4a: ModsMenu.tscn loads")
	if packed == null:
		_finish()
		return
	_menu = packed.instantiate() as Control
	get_tree().root.add_child(_menu)
	await _settle()
	var script: Script = _menu.get_script() as Script
	_check(script != null and script.resource_path == "res://scripts/ModsMenu.gd",
		"T4: ModsMenu uses the real script, not PlaceholderScreen.gd")
	var title := _node("TitleLabel") as Label
	_check(title != null and title.text == "Mods Menu", "T5: title label reads Mods Menu")
	var expected_nodes: Array = [
		"ModScroll", "ModScroll/ModBox", "RestartNotice", "BackButton",
	]
	var structure_ok: bool = true
	for path in expected_nodes:
		if _node(path) == null:
			structure_ok = false
	_check(structure_ok, "T6: scroll host, restart notice and Back button exist")

	# --- One row per mod, with metadata and status ----------------------------
	var rows_ok: bool = true
	for i in _snapshot.size():
		var prefix: String = "ModScroll/ModBox/ModRow_%d/" % i
		if (_node(prefix + "NameLabel") == null or _node(prefix + "MetaLabel") == null
			or _node(prefix + "StatusLabel") == null or _node(prefix + "ToggleButton") == null):
			rows_ok = false
	_check(rows_ok, "T7: each mod has a stable ModRow_<index> with its four controls")
	var base_row: int = _row_index("menu:base")
	var name_label := _node("ModScroll/ModBox/ModRow_%d/NameLabel" % base_row) as Label
	var meta_label := _node("ModScroll/ModBox/ModRow_%d/MetaLabel" % base_row) as Label
	_check(name_label != null and name_label.text.contains("Base Mod")
		and meta_label != null and meta_label.text.contains("1.2.3")
		and meta_label.text.contains("Tester"),
		"T8: the row shows the mod's authored name, version and author")
	var disabled_row: int = _row_index("menu:disabled")
	var status_label := _node("ModScroll/ModBox/ModRow_%d/StatusLabel" % disabled_row) as Label
	_check(status_label != null and status_label.text.contains("Skipped")
		and status_label.text.contains("disabled (settings flag)"),
		"T9: the status label shows a skipped mod's diagnostic reason")

	# --- Toggle states come from settings, not from the live load -------------
	var base_toggle := _node("ModScroll/ModBox/ModRow_%d/ToggleButton" % base_row) as CheckButton
	var disabled_toggle := _node("ModScroll/ModBox/ModRow_%d/ToggleButton" % disabled_row) as CheckButton
	var user_toggle := _node("ModScroll/ModBox/ModRow_%d/ToggleButton" % _row_index("menu:user")) as CheckButton
	_check(base_toggle != null and base_toggle.button_pressed
		and disabled_toggle != null and not disabled_toggle.button_pressed
		and user_toggle != null and user_toggle.button_pressed,
		"T10: toggles reflect stored settings flags (disabled mod is off)")

	# --- Toggling writes settings, shows a notice and does NOT rescan ---------
	var loaded_before: Array = ModLoader.get_loaded_mods().duplicate()
	var snapshot_before: Array = ModLoader.get_installed_mods()
	base_toggle.button_pressed = false
	var notice := _node("RestartNotice") as Label
	_check(not SettingsManager.get_mod_enabled("menu:base")
		and bool(SettingsManager.get_mod_flags().get("menu:base", true)) == false,
		"T11: disabling a mod writes a false flag to settings")
	_check(notice != null and notice.visible
		and notice.text.to_lower().contains("restart"),
		"T12: toggling shows a restart-required notice")
	_check(ModLoader.get_loaded_mods() == loaded_before
		and ModLoader.get_installed_mods() == snapshot_before
		and _entry("menu:base").get("status", "") == "loaded",
		"T13: toggling does not rescan live or change the session's load status")

	# Enabling clears the flag (absence == default enabled).
	disabled_toggle.button_pressed = true
	_check(SettingsManager.get_mod_enabled("menu:disabled")
		and not SettingsManager.get_mod_flags().has("menu:disabled")
		and notice != null and notice.visible,
		"T14: enabling removes the flag and keeps the restart notice")

	# --- Next launch applies the flags and dependency satisfaction -----------
	ModLoader.load_mods_from_roots([ROOT_A, ROOT_B])
	var after: Array = ModLoader.get_installed_mods()
	_check(_find(after, "menu:base").get("status", "") == "skipped"
		and str(_find(after, "menu:base").get("reason", "")).contains("disabled (settings flag)"),
		"T15: a disabled mod is excluded on the next launch")
	_check(_find(after, "menu:disabled").get("status", "") == "loaded",
		"T16: an enabled mod loads on the next launch")
	_check(_find(after, "menu:needs_disabled").get("status", "") == "loaded",
		"T17: an enabled mod satisfies a dependent's dependency next launch")

	# --- Invalid mods stay visible but cannot be toggled ---------------------
	var bad_row: int = _row_index("bad_manifest")
	var bad_status := _node("ModScroll/ModBox/ModRow_%d/StatusLabel" % bad_row) as Label
	var bad_toggle := _node("ModScroll/ModBox/ModRow_%d/ToggleButton" % bad_row) as CheckButton
	var no_manifest_row: int = _row_index("no_manifest")
	var no_manifest_status := _node("ModScroll/ModBox/ModRow_%d/StatusLabel" % no_manifest_row) as Label
	_check(bad_status != null and bad_status.text.contains("required field 'author'")
		and no_manifest_status != null and no_manifest_status.text.contains("missing mod.json")
		and bad_toggle != null and bad_toggle.disabled,
		"T18: invalid/skipped mods show their reason with a non-interactive toggle")

	# --- Back seam (injected action + default Main Menu route) ---------------
	var back_button := _node("BackButton") as Button
	_check(_menu.has_method("set_back_action") and back_button != null,
		"T19: Back seam exists for the pause overlay's in-place embedding")
	_menu.set_back_action(Callable(self, "_record_back"))
	back_button.pressed.emit()
	_check(_back_calls == 1, "T20: an injected Back action is called exactly once")
	_menu.set_back_action(Callable())
	var swaps_before: int = GameManager.scene_change_count
	back_button.pressed.emit()
	await _settle()
	var current := get_tree().current_scene
	_check(_menu.back_action.is_valid()
		and GameManager.scene_change_count == swaps_before + 1
		and current != null and current.name == "MainMenu",
		"T21: an invalid Back action restores the Main Menu route")

	_check(_executed == EXPECTED_CHECKS - 1, "T22: all expected 031 checks executed")
	_cleanup()
	_finish()


## --- Fixtures ---------------------------------------------------------------

func _make_fixtures() -> void:
	_write_mod(ROOT_A, "base", "menu:base", "Base Mod", "1.2.3", "Tester", [])
	_write_mod(ROOT_A, "disabled", "menu:disabled", "Disabled Mod", "2.0", "Tester", [])
	_write_mod(ROOT_A, "needs_disabled", "menu:needs_disabled", "Needs Disabled", "1.0", "Tester", ["menu:disabled"])
	_write_mod(ROOT_B, "user", "menu:user", "User Mod", "0.9", "User", ["menu:base"])
	var bad: Dictionary = _manifest("menu:bad", "Bad Mod", "1.0", "Nobody", [], "entry.gd")
	bad.erase("author")
	_write_text(ROOT_B + "bad_manifest/mod.json", JSON.stringify(bad))
	_write_text(ROOT_B + "bad_manifest/entry.gd", _entry_code())
	# A folder with no manifest at all is still visible with its diagnostic.
	_write_text(ROOT_B + "no_manifest/readme.txt", "not a mod")


func _manifest(id: String, name: String, version: String, author: String,
		deps: Array, entry: String) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"version": version,
		"author": author,
		"entry": entry,
		"dependencies": deps,
		"content": [],
	}


func _entry_code() -> String:
	return "extends RefCounted\n## No-op entry for a ticket 031 fixture.\nfunc register(_loader) -> void:\n\tpass\n"


func _write_mod(root: String, folder: String, id: String, name: String,
		version: String, author: String, deps: Array) -> void:
	_write_text(root + folder + "/mod.json", JSON.stringify(_manifest(id, name, version, author, deps, "entry.gd")))
	_write_text(root + folder + "/entry.gd", _entry_code())


func _write_text(path: String, text: String) -> void:
	var folder: String = path.substr(0, path.rfind("/"))
	DirAccess.make_dir_recursive_absolute(folder)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


## --- Helpers -----------------------------------------------------------------

func _entry(mod_id: String) -> Dictionary:
	for item_variant in _snapshot:
		var item: Dictionary = item_variant
		if str(item.get("id", "")) == mod_id:
			return item
	return {}


func _find(snapshot: Array, mod_id: String) -> Dictionary:
	for item_variant in snapshot:
		var item: Dictionary = item_variant
		if str(item.get("id", "")) == mod_id:
			return item
	return {}


func _row_index(mod_id: String) -> int:
	for i in _snapshot.size():
		if str((_snapshot[i] as Dictionary).get("id", "")) == mod_id:
			return i
	return 0


func _node(path: String) -> Node:
	return _menu.get_node_or_null(path) if _menu != null else null


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _remove_dir_recursive(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var child: String = path + entry
		if dir.current_is_dir():
			_remove_dir_recursive(child + "/")
		else:
			DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _cleanup() -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_remove_dir_recursive(ROOT_A)
	_remove_dir_recursive(ROOT_B)
	_remove_file(SETTINGS_PATH)
	SettingsManager.set_config_path(SettingsManager.CONFIG_PATH)
	ModLoader.load_mods()


## --- Assertion / completion -------------------------------------------------

func _check(ok: bool, label: String) -> void:
	_executed += 1
	if ok:
		_passed += 1
		print("[031] PASS " + label)
	else:
		_failed += 1
		print("[031] FAIL " + label)


func _finish() -> void:
	print("[031] RESULT passed=%d failed=%d" % [_passed, _failed])
	if _failed == 0:
		print("ALL_031_CHECKS_PASSED")
	else:
		print("SOME_031_CHECKS_FAILED")
	get_tree().quit(0 if _failed == 0 else 1)
