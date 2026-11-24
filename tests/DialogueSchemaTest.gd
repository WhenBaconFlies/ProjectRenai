## DialogueSchemaTest
##
## Persistent headless acceptance harness for ticket 021. It verifies the two new
## dialogue resource schemas at the seams a developer or modder actually uses:
## field-by-field ResourceSaver/ResourceLoader round-trips, the line-only rule,
## editor class registration, add-only registry buckets, and mod loading of both
## new types. Prints ALL_021_CHECKS_PASSED only when every assertion passed.
extends Node


## --- Fixture paths ----------------------------------------------------------

const GREETING_PATH: String = "user://dialogue_schema_greeting.tres"
const RESPONSE_PATH: String = "user://dialogue_schema_response.tres"
const MODS_ROOT: String = "user://dialogue_schema_mods/"
const MOD_FOLDER: String = MODS_ROOT + "test_dialogue/"
const MOD_GREETING_PATH: String = MOD_FOLDER + "greeting_mod_test.tres"
const MOD_RESPONSE_PATH: String = MOD_FOLDER + "response_mod_test.tres"
const MOD_MANIFEST_PATH: String = MOD_FOLDER + "mod.json"

## T1..T21 plus T22 (schema default weight) and T23 (completeness self-check).
const EXPECTED_CHECKS: int = 23

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(_global_classes_registered(), "T1: both new classes are registered for the editor New Resource dialog")
	_check(_exports_documented("res://scripts/DialogueGreeting.gd"), "T2: every DialogueGreeting export field is typed and documented")
	_check(_exports_documented("res://scripts/DialogueResponse.gd"), "T3: every DialogueResponse export field is typed and documented")
	_check(_round_trip_greeting(), "T4: DialogueGreeting round-trips all fields through a .tres")
	_check(_round_trip_response(), "T5: DialogueResponse round-trips all fields through a .tres")
	_check_line_only_rule()
	_check_base_samples()
	_check_registry_buckets()
	_check_mod_registration()
	_check(DialogueGreeting.new().weight == 1.0, "T22: DialogueGreeting schema default weight is 1.0")
	_cleanup()
	_finish()


## --- Field round-trips ------------------------------------------------------

## Save and reload a greeting with every field set to a distinct value, then
## compare field by field so a swapped or dropped field cannot pass.
func _round_trip_greeting() -> bool:
	var source := DialogueGreeting.new()
	source.id = "greeting:roundtrip"
	source.text = "Round-trip greeting line"
	source.relationship_types = PackedStringArray(["Friend", "Lover"])
	source.min_mood = 25
	source.max_mood = 90
	source.periods = PackedStringArray(["FREETIME1", "FREETIME2"])
	source.required_traits = PackedStringArray(["trait:outgoing"])
	source.required_interests = PackedStringArray(["interest:likes_sports"])
	source.weight = 1.75
	if ResourceSaver.save(source, GREETING_PATH) != OK:
		return false
	var loaded := ResourceLoader.load(GREETING_PATH) as DialogueGreeting
	if loaded == null:
		return false
	return (
		loaded.id == source.id
		and loaded.text == source.text
		and _same_strings(loaded.relationship_types, source.relationship_types)
		and loaded.min_mood == source.min_mood
		and loaded.max_mood == source.max_mood
		and _same_strings(loaded.periods, source.periods)
		and _same_strings(loaded.required_traits, source.required_traits)
		and _same_strings(loaded.required_interests, source.required_interests)
		and is_equal_approx(loaded.weight, source.weight)
	)


func _round_trip_response() -> bool:
	var source := DialogueResponse.new()
	source.id = "response:roundtrip"
	source.text = "Round-trip response line"
	source.topic_id = "topic:compliment"
	source.outcomes = PackedStringArray(["success", "failure"])
	source.relationship_bands = PackedStringArray(["Acquaintance", "Friend", "Lover"])
	source.checked_stat = "charisma"
	source.difficulty = 7
	source.affection_delta_success = 3
	source.familiarity_delta_success = 2
	source.mood_delta_success = 4
	source.affection_delta_failure = -3
	source.familiarity_delta_failure = 1
	source.mood_delta_failure = -5
	if ResourceSaver.save(source, RESPONSE_PATH) != OK:
		return false
	var loaded := ResourceLoader.load(RESPONSE_PATH) as DialogueResponse
	if loaded == null:
		return false
	return (
		loaded.id == source.id
		and loaded.text == source.text
		and loaded.topic_id == source.topic_id
		and _same_strings(loaded.outcomes, source.outcomes)
		and _same_strings(loaded.relationship_bands, source.relationship_bands)
		and loaded.checked_stat == source.checked_stat
		and loaded.difficulty == source.difficulty
		and loaded.affection_delta_success == source.affection_delta_success
		and loaded.familiarity_delta_success == source.familiarity_delta_success
		and loaded.mood_delta_success == source.mood_delta_success
		and loaded.affection_delta_failure == source.affection_delta_failure
		and loaded.familiarity_delta_failure == source.familiarity_delta_failure
		and loaded.mood_delta_failure == source.mood_delta_failure
	)


## --- Line-only contract -----------------------------------------------------

func _check_line_only_rule() -> void:
	var empty_stat := DialogueResponse.new()
	empty_stat.checked_stat = ""
	empty_stat.difficulty = 9
	empty_stat.affection_delta_success = 5
	_check(empty_stat.is_line_only(), "T6: empty checked_stat is line-only even with authored roll fields")
	var zero_delta_roll := DialogueResponse.new()
	zero_delta_roll.checked_stat = "charisma"
	zero_delta_roll.difficulty = 0
	zero_delta_roll.affection_delta_success = 0
	_check(not zero_delta_roll.is_line_only(), "T7: an intentional zero-delta roll is not line-only")
	var round_trip_response := ResourceLoader.load(RESPONSE_PATH) as DialogueResponse
	_check(round_trip_response != null and not round_trip_response.is_line_only(), "T8: a populated checked_stat round-trips as rollable")


## --- Authored base content and registry ------------------------------------

func _check_base_samples() -> void:
	var generic := ModLoader.get_resource(ModLoader.TYPE_GREETING, "greeting:generic") as DialogueGreeting
	var gated := ModLoader.get_resource(ModLoader.TYPE_GREETING, "greeting:friend_free_time") as DialogueGreeting
	_check(generic != null and generic.weight == 1.0, "T9: generic greeting base sample registered with authored weight 1.0")
	_check(
		gated != null and gated.relationship_types.has("Friend") and gated.periods.has("FREETIME1") and gated.weight == 1.5,
		"T10: gated greeting base sample registered with its eligibility fields"
	)
	var line_only := ModLoader.get_resource(ModLoader.TYPE_RESPONSE, "response:generic") as DialogueResponse
	var rollable := ModLoader.get_resource(ModLoader.TYPE_RESPONSE, "response:ask_day_success_friend") as DialogueResponse
	_check(line_only != null and line_only.is_line_only() and line_only.topic_id.is_empty(), "T11: line-only response base sample is generic")
	_check(
		rollable != null and not rollable.is_line_only() and rollable.topic_id == "topic:ask_day" and rollable.outcomes.has("success"),
		"T12: rollable response base sample keeps its key and roll fields"
	)


func _check_registry_buckets() -> void:
	_check(ModLoader.get_all(ModLoader.TYPE_GREETING).size() >= 2, "T13: TYPE_GREETING bucket holds authored greetings")
	_check(ModLoader.get_all(ModLoader.TYPE_RESPONSE).size() >= 2, "T14: TYPE_RESPONSE bucket holds authored responses")
	_check(ModLoader.get_all(ModLoader.TYPE_DIALOGUE).size() >= 2, "T15: existing TYPE_DIALOGUE bucket is unaffected")
	var duplicate := DialogueGreeting.new()
	duplicate.id = "greeting:generic"
	duplicate.text = "OVERRIDE"
	var original := ModLoader.get_resource(ModLoader.TYPE_GREETING, "greeting:generic") as DialogueGreeting
	_check(not ModLoader.register_resource(ModLoader.TYPE_GREETING, duplicate, "test"), "T16: duplicate greeting id is rejected add-only")
	_check(original != null and not (original as DialogueGreeting).text.contains("OVERRIDE"), "T17: rejected duplicate does not replace the original")


## --- Mod loading of the new types ------------------------------------------

func _check_mod_registration() -> void:
	_make_mod_fixture()
	ModLoader.load_mods(MODS_ROOT)
	var mod_greeting := ModLoader.get_resource(ModLoader.TYPE_GREETING, "greeting:mod_test") as DialogueGreeting
	var mod_response := ModLoader.get_resource(ModLoader.TYPE_RESPONSE, "response:mod_test") as DialogueResponse
	_check(mod_greeting != null, "T18: a mod .tres registers into TYPE_GREETING")
	_check(mod_response != null and not mod_response.is_line_only(), "T19: a mod .tres registers into TYPE_RESPONSE with roll fields")
	_check(ModLoader.get_resource(ModLoader.TYPE_GREETING, "greeting:generic") != null, "T20: base greetings survive a re-scan")
	_check(ModLoader.get_loaded_mods().has("test_dialogue_mod"), "T21: the synthetic mod loaded successfully")
	ModLoader.load_mods()


func _make_mod_fixture() -> void:
	var root_dir: DirAccess = DirAccess.open("user://")
	if root_dir == null:
		return
	root_dir.make_dir("dialogue_schema_mods")
	var mod_dir: DirAccess = DirAccess.open(MODS_ROOT)
	if mod_dir == null:
		return
	mod_dir.make_dir("test_dialogue")

	var greeting := DialogueGreeting.new()
	greeting.id = "greeting:mod_test"
	greeting.text = "Mod greeting"
	greeting.weight = 2.0
	if ResourceSaver.save(greeting, MOD_GREETING_PATH) != OK:
		push_error("[021] cannot write mod greeting fixture")
		return
	var response := DialogueResponse.new()
	response.id = "response:mod_test"
	response.text = "Mod reply"
	response.topic_id = "topic:ask_day"
	response.checked_stat = "wisdom"
	response.difficulty = 4
	if ResourceSaver.save(response, MOD_RESPONSE_PATH) != OK:
		push_error("[021] cannot write mod response fixture")
		return

	var manifest: Dictionary = {
		"id": "test_dialogue_mod",
		"name": "Test Dialogue Mod",
		"version": "1.0.0",
		"author": "Project Renai",
		"entry": "res://tests/DialogueSchemaModEntry.gd",
		"dependencies": [],
		"content": [MOD_GREETING_PATH, MOD_RESPONSE_PATH],
	}
	var file: FileAccess = FileAccess.open(MOD_MANIFEST_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(manifest))
		file.close()


func _cleanup() -> void:
	for path in [GREETING_PATH, RESPONSE_PATH, MOD_GREETING_PATH, MOD_RESPONSE_PATH, MOD_MANIFEST_PATH, MOD_FOLDER, MODS_ROOT]:
		_remove(path)


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	elif DirAccess.dir_exists_absolute(path):
		DirAccess.remove_absolute(path)


## --- Static documentation / class checks -----------------------------------

func _global_classes_registered() -> bool:
	var found: int = 0
	for entry in ProjectSettings.get_global_class_list():
		if str((entry as Dictionary).get("class", "")) in ["DialogueGreeting", "DialogueResponse"]:
			found += 1
	return found == 2


## Every @export line must carry a typed declaration and a `##` doc comment on
## the immediately preceding non-empty line — ticket 021's last checkbox.
func _exports_documented(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var count: int = 0
	for i in range(lines.size()):
		var stripped: String = lines[i].strip_edges()
		if not stripped.begins_with("@export var "):
			continue
		count += 1
		if not stripped.contains(": "):
			print("[021] untyped export in %s: %s" % [path, stripped])
			return false
		var previous: int = i - 1
		while previous >= 0 and lines[previous].strip_edges().is_empty():
			previous -= 1
		if previous < 0 or not lines[previous].strip_edges().begins_with("##"):
			print("[021] undocumented export in %s: %s" % [path, stripped])
			return false
	return count > 0


## --- Assertion / completion -------------------------------------------------

func _same_strings(a: PackedStringArray, b: PackedStringArray) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("[021] PASS " + label)
	else:
		_failed += 1
		print("[021] FAIL " + label)


func _finish() -> void:
	# Guards against a truncated _run() printing the authoritative pass marker.
	_check(_passed == EXPECTED_CHECKS - 1, "T23: all expected 021 checks executed")
	print("[021] RESULT passed=%d failed=%d" % [_passed, _failed])
	if _failed == 0:
		print("ALL_021_CHECKS_PASSED")
	else:
		print("SOME_021_CHECKS_FAILED")
	get_tree().quit(0 if _failed == 0 else 1)
