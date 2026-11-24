## ModLoaderDualRootTest
##
## Persistent headless acceptance harness for ticket 029. It drives the real
## ModLoader autoload through two synthetic mod trees (standing in for the
## bundled res:// root and the user-writable user:// root) and asserts only
## observable behaviour: resources registered from both roots, cross-root
## dependency order, settings-based disabling, the ignored .disabled marker,
## add-only duplicate diagnostics, cycles, entry hooks and the report shape.
## Settings storage is redirected to a fixture so the real settings.cfg is never
## touched. Prints ALL_029_CHECKS_PASSED only when every assertion passed.
extends Node

const ROOT_A: String = "user://modloader029_root_a/"
const ROOT_B: String = "user://modloader029_root_b/"
const SETTINGS_PATH: String = "user://modloader029_settings.cfg"
const ENTRY_MARKER: String = "user://modloader029_entry_marker.txt"

const EXPECTED_CHECKS: int = 20

var _passed: int = 0
var _failed: int = 0
## Executed checks are counted separately so one defect reports one failure.
var _executed: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# RED guard: a run against the old ModLoader must fail as a normal assertion
	# with the pass/fail marker, not abort on a missing-method runtime error.
	if not ModLoader.has_method("get_mods_roots") or not ModLoader.has_method("load_mods_from_roots"):
		_check(false, "T0: ModLoader exposes the dual-root API")
		_finish()
		return
	_check(true, "T0: ModLoader exposes the dual-root API")

	_remove_file(SETTINGS_PATH)
	SettingsManager.set_config_path(SETTINGS_PATH)
	_clear_empty_user_mods_root()

	# --- Default scan roots ---------------------------------------------------
	ModLoader.load_mods()
	var roots: Array = ModLoader.get_mods_roots()
	_check(roots.has("res://mods/") and roots.has("user://mods/"),
		"T1: load_mods() scans both the bundled and user-writable roots")
	_check(DirAccess.dir_exists_absolute("user://mods/"),
		"T17: a missing user mods root is created on startup")
	_check(ModLoader.get_mods_root() == "res://mods/",
		"T1b: get_mods_root() still reports the bundled root for v1 callers")

	_make_fixtures()
	SettingsManager.set_mod_enabled("dual:disabled", false)
	SettingsManager.set_mod_enabled("dual:cycle_disabled_a", false)
	SettingsManager.set_mod_enabled("dual:user_disabled", false)
	ModLoader.load_mods_from_roots([ROOT_A, ROOT_B])

	# --- Registration from both roots ----------------------------------------
	_check(ModLoader.has_resource(ModLoader.TYPE_DIALOGUE, "topic:dual_base")
		and ModLoader.has_resource(ModLoader.TYPE_DIALOGUE, "topic:dual_user_dep"),
		"T2: resources from both roots register into the same typed bucket")

	var loaded: Array = ModLoader.get_loaded_mods()
	var dep_index: int = loaded.find("dual:user_dep")
	var dependent_index: int = loaded.find("dual:depends")
	_check(dep_index >= 0 and dependent_index >= 0 and dep_index < dependent_index,
		"T3: a mod in the bundled root loads after its dependency in the user root")

	# --- Enable/disable source ------------------------------------------------
	_check(not ModLoader.has_resource(ModLoader.TYPE_DIALOGUE, "topic:dual_disabled")
		and _report_has("dual:disabled", "skipped", "disabled"),
		"T4: a settings flag disables a mod with a logged diagnostic")
	_check(ModLoader.has_resource(ModLoader.TYPE_DIALOGUE, "topic:dual_marker")
		and loaded.has("dual:marker"),
		"T5: a .disabled marker no longer excludes a mod")

	# --- Add-only duplicates across roots ------------------------------------
	_check(loaded.has("dual:duplicate")
		and ModLoader.has_resource(ModLoader.TYPE_DIALOGUE, "topic:dual_dup_a")
		and not ModLoader.has_resource(ModLoader.TYPE_DIALOGUE, "topic:dual_dup_b")
		and _report_has_prefix("dual:duplicate", "skipped", "duplicate"),
		"T6: the bundled duplicate id wins and the user copy is skipped with a diagnostic")
	var bundled_topic: DialogueTopic = ModLoader.get_resource(ModLoader.TYPE_DIALOGUE, "topic:dual_base") as DialogueTopic
	_check(bundled_topic != null and bundled_topic.text == "bundled base text",
		"T7: a duplicate resource id is rejected add-only, keeping the first root's resource")

	# --- Dependency/cycle handling -------------------------------------------
	_check(not loaded.has("dual:cycle_a") and not loaded.has("dual:cycle_b")
		and _report_has("dual:cycle_a", "skipped", "cyclic")
		and _report_has("dual:cycle_b", "skipped", "cyclic"),
		"T8: cycles spanning roots are detected and skipped cleanly")
	var report: Array = ModLoader.get_last_report()
	var disabled_cycle_reported: bool = false
	for entry_variant in report:
		var entry: Dictionary = entry_variant
		var mod_id: String = str(entry.get("mod", ""))
		if (mod_id.begins_with("dual:cycle_disabled")
			and str(entry.get("reason", "")).contains("cyclic")):
			disabled_cycle_reported = true
	_check(not disabled_cycle_reported,
		"T8b: a disabled mod is filtered before cycle detection")
	_check(not loaded.has("dual:needs_disabled")
		and _report_has("dual:needs_disabled", "skipped", "missing dependency"),
		"T9: a disabled mod does not satisfy another mod's dependency")

	# --- Root priority beats incidental topological load order ---------------
	var conflict_topic: DialogueTopic = ModLoader.get_resource(ModLoader.TYPE_DIALOGUE, "topic:dual_conflict") as DialogueTopic
	_check(conflict_topic != null and conflict_topic.text == "bundled conflict",
		"T14: a bundled resource wins a duplicate id even when the user copy registers first")

	_check(not loaded.has("dual:user_disabled")
		and not ModLoader.has_resource(ModLoader.TYPE_DIALOGUE, "topic:dual_user_disabled")
		and _report_has("dual:user_disabled", "skipped", "disabled"),
		"T15: a settings flag disables a mod in the user-writable root")
	_check(not loaded.has("dual:manifest_disabled")
		and _report_has("dual:manifest_disabled", "skipped", "manifest enabled=false"),
		"T16: a manifest enabled=false disables a mod in the user-writable root")

	# --- Entry hooks and diagnostics -----------------------------------------
	_remove_file(ENTRY_MARKER)
	ModLoader.load_mods_from_roots([ROOT_A, ROOT_B])
	var marker_file: FileAccess = FileAccess.open(ENTRY_MARKER, FileAccess.READ)
	var marker_text: String = marker_file.get_as_text() if marker_file != null else ""
	if marker_file != null:
		marker_file.close()
	_check(marker_text == "dual:entry",
		"T10: an entry hook from the user root still runs")
	_check(not report.is_empty() and report[0] is Dictionary
		and (report[0] as Dictionary).has("status")
		and (report[0] as Dictionary).has("reason"),
		"T11: get_last_report() still exposes structured diagnostics")

	# --- Single-root compatibility seam --------------------------------------
	ModLoader.load_mods(ROOT_B)
	_check(ModLoader.has_resource(ModLoader.TYPE_DIALOGUE, "topic:dual_user_dep")
		and not ModLoader.has_resource(ModLoader.TYPE_DIALOGUE, "topic:dual_dup_a"),
		"T12: load_mods(single_path) keeps the v1 one-root test seam")

	_check(_executed == EXPECTED_CHECKS - 1,
		"T13: all expected 029 checks executed")
	_cleanup()
	_finish()


## --- Fixtures ---------------------------------------------------------------

func _make_fixtures() -> void:
	_write_mod(ROOT_A, "base", "dual:base", [], ["topic:dual_base"], "bundled base text")
	_write_mod(ROOT_A, "depends", "dual:depends", ["dual:user_dep"], ["topic:dual_dep"], "bundled dependent")
	_write_mod(ROOT_A, "disabled", "dual:disabled", [], ["topic:dual_disabled"], "disabled text")
	_write_mod(ROOT_A, "duplicate", "dual:duplicate", [], ["topic:dual_dup_a"], "bundled duplicate")
	_write_mod(ROOT_A, "marker", "dual:marker", [], ["topic:dual_marker"], "marked text")
	_write_text(ROOT_A + "marker/.disabled", "")
	# Bundled mod that depends on a user-root mod: it loads after the user root,
	# but its resource id must still win the add-only conflict (T14).
	_write_mod(ROOT_A, "dep_conflict", "dual:dep_conflict", ["dual:user_dep"], ["topic:dual_conflict"], "bundled conflict")
	_write_mod(ROOT_A, "cycle_a", "dual:cycle_a", ["dual:cycle_b"], [], "cycle a")

	_write_mod(ROOT_B, "user_dep", "dual:user_dep", [], ["topic:dual_user_dep"], "user dependency")
	_write_mod(ROOT_B, "user_dup", "dual:duplicate", [], ["topic:dual_dup_b"], "user duplicate")
	_write_mod(ROOT_B, "resource_dup", "dual:resource_dup", [], ["topic:dual_base"], "user resource duplicate")
	_write_mod(ROOT_B, "user_conflict", "dual:user_conflict", [], ["topic:dual_conflict"], "user conflict")
	_write_mod(ROOT_B, "user_disabled", "dual:user_disabled", [], ["topic:dual_user_disabled"], "user disabled text")
	_write_mod(ROOT_B, "manifest_disabled", "dual:manifest_disabled", [], ["topic:dual_manifest_disabled"], "manifest disabled text", false)
	_write_mod(ROOT_B, "cycle_b", "dual:cycle_b", ["dual:cycle_a"], [], "cycle b")
	_write_mod(ROOT_B, "cycle_disabled_a", "dual:cycle_disabled_a", ["dual:cycle_disabled_b"], [], "disabled cycle a")
	_write_mod(ROOT_B, "cycle_disabled_b", "dual:cycle_disabled_b", ["dual:cycle_disabled_a"], [], "disabled cycle b")
	_write_mod(ROOT_B, "needs_disabled", "dual:needs_disabled", ["dual:disabled"], [], "needs disabled")

	var entry_code: String = (
		"extends RefCounted\n"
		+ "## Test-only entry: records that an entry hook from the user root ran.\n"
		+ "func register(_loader) -> void:\n"
		+ "\tvar file: FileAccess = FileAccess.open(\"%s\", FileAccess.WRITE)\n" % ENTRY_MARKER
		+ "\tif file != null:\n"
		+ "\t\tfile.store_string(\"dual:entry\")\n"
		+ "\t\tfile.close()\n"
	)
	_write_mod(ROOT_B, "entry", "dual:entry", [], ["topic:dual_entry"], "entry topic")
	_write_text(ROOT_B + "entry/entry.gd", entry_code)


func _write_mod(root: String, folder: String, mod_id: String, deps: Array,
		contents: Array, text: String, enabled_variant: Variant = null) -> void:
	var manifest: Dictionary = {
		"id": mod_id,
		"name": "Fixture " + folder,
		"version": "1.0.0",
		"author": "029-test",
		"entry": "entry.gd",
		"dependencies": deps,
		"content": [],
	}
	var content_index: int = 0
	for content_id in contents:
		var filename: String = "content_%d.tres" % content_index
		var resource_path: String = root + folder + "/" + filename
		_write_text(resource_path, _topic_resource(str(content_id), text))
		manifest["content"].append(filename)
		content_index += 1
	if enabled_variant != null:
		manifest["enabled"] = enabled_variant
	_write_text(root + folder + "/mod.json", JSON.stringify(manifest))
	_write_text(root + folder + "/entry.gd",
		"extends RefCounted\n## No-op entry for a ticket 029 fixture.\nfunc register(_loader) -> void:\n\tpass\n")


func _topic_resource(topic_id: String, text: String) -> String:
	return (
		'[gd_resource type="Resource" script_class="DialogueTopic" load_steps=2 format=3]\n\n'
		+ '[ext_resource type="Script" path="res://scripts/DialogueTopic.gd" id="1_topic"]\n\n'
		+ '[resource]\nscript = ExtResource("1_topic")\n'
		+ 'id = "%s"\n' % topic_id
		+ 'text = "%s"\n' % text
		+ 'min_mood = 0\nmin_familiarity = 0\nmin_affection = 0\n'
		+ 'required_interests = PackedStringArray()\nrequired_traits = PackedStringArray()\n'
		+ 'required_stat = ""\nrequired_stat_min = 0\n'
		+ 'checked_stat = "wisdom"\ndifficulty = 1\n'
		+ 'affection_delta_success = 1\nfamiliarity_delta_success = 1\nmood_delta_success = 1\n'
		+ 'affection_delta_failure = 0\nfamiliarity_delta_failure = 0\nmood_delta_failure = 0\n'
	)


func _write_text(path: String, text: String) -> void:
	var folder: String = path.substr(0, path.rfind("/"))
	DirAccess.make_dir_recursive_absolute(folder)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Start from a genuinely missing user root, but never delete real user mods.
func _clear_empty_user_mods_root() -> void:
	var dir: DirAccess = DirAccess.open("user://mods/")
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	var empty: bool = true
	while entry != "":
		if entry != "." and entry != "..":
			empty = false
		entry = dir.get_next()
	dir.list_dir_end()
	if empty:
		DirAccess.remove_absolute("user://mods/")


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


func _report_has(mod_id: String, status: String, reason_fragment: String) -> bool:
	for entry_variant in ModLoader.get_last_report():
		var entry: Dictionary = entry_variant
		if (str(entry.get("mod", "")) == mod_id
			and str(entry.get("status", "")) == status
			and str(entry.get("reason", "")).contains(reason_fragment)):
			return true
	return false


## Discovery-stage skips use a composite `id@folder` key so two mods with the
## same id in different roots produce distinct diagnostics.
func _report_has_prefix(mod_id: String, status: String, reason_fragment: String) -> bool:
	for entry_variant in ModLoader.get_last_report():
		var entry: Dictionary = entry_variant
		if (str(entry.get("mod", "")).begins_with(mod_id)
			and str(entry.get("status", "")) == status
			and str(entry.get("reason", "")).contains(reason_fragment)):
			return true
	return false


func _cleanup() -> void:
	_remove_dir_recursive(ROOT_A)
	_remove_dir_recursive(ROOT_B)
	_remove_file(ENTRY_MARKER)
	_remove_file(SETTINGS_PATH)
	SettingsManager.set_config_path(SettingsManager.CONFIG_PATH)
	ModLoader.load_mods()


## --- Assertion / completion -------------------------------------------------

func _check(ok: bool, label: String) -> void:
	_executed += 1
	if ok:
		_passed += 1
		print("[029] PASS " + label)
	else:
		_failed += 1
		print("[029] FAIL " + label)


func _finish() -> void:
	print("[029] RESULT passed=%d failed=%d" % [_passed, _failed])
	if _failed == 0:
		print("ALL_029_CHECKS_PASSED")
	else:
		print("SOME_029_CHECKS_FAILED")
	get_tree().quit(0 if _failed == 0 else 1)
