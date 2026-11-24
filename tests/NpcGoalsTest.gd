## NpcGoalsTest
##
## Persistent headless acceptance harness for ticket 032. Drives NpcAi with
## authored meters and synthetic maps at the same seam Game uses, checking that
## directed familiarity/affection weight seeded free-time goals: seek friends and
## lovers (including the player), avoid enemies, keep the v1 interest/mood path,
## and never crash on empty/malformed data or stale markers.
## Prints ALL_032_CHECKS_PASSED only when every assertion passed.
extends Node


const EXPECTED_CHECKS: int = 17
## Number of seeded samples per distribution check. Small enough to stay fast,
## large enough that a +5/+8 weight dominates the base weight of 1.
const SAMPLES: int = 64

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(_empty_candidates(), "T1: no meters / no roster yields no relationship candidates")
	_check(_classified("Friend", 25, 25, 5), "T2: familiarity+affection 25 yields a Friend candidate of weight 5")
	_check(_classified("Lover", 65, 65, 8), "T3: familiarity+affection 65 yields a Lover candidate of weight 8")
	_check(_classified("Enemy", 0, -25, -100), "T4: affection -25 yields an Enemy candidate of weight -100")
	_check(_weak_and_malformed_meters(), "T5: Stranger/Acquaintance/malformed meters yield no candidate")
	_check(_seek_distribution("Friend", 25, 25, "hangout:library"), "T6: a Friend hangout is sought more often than baseline or rivals")
	_check(_seek_distribution("Lover", 65, 65, "hangout:garden"), "T7: a Lover hangout is sought more often than baseline or rivals")
	_check(_avoid_hangout(), "T8: an Enemy hangout is never chosen while three rivals exist")
	_check(_degenerate_all_enemy(), "T9: an all-enemy single-marker map still returns a hangout goal")
	_check(_seek_player(), "T10: a Lover meter toward the player seeks player.position with no hangouts")
	_check(_avoid_player(), "T11: an Enemy meter toward the player never targets the player")
	_check(_v1_mood_path_preserved(), "T12: low mood still favours quiet hangouts when meters are empty")
	_check(_deterministic(), "T13: identical seed/eval/roster yields an identical goal and destination")
	_check(_stale_marker_fallback(), "T14: a missing candidate marker falls back to a valid hangout without crashing")
	_check(_defensive_roster(), "T15: null/foreign/self/duplicate roster entries are ignored")
	_check(_node_wiring(), "T16: an Npc node with a roster seeks the friend's hangout through set_ai_enabled")
	_check(_passed == EXPECTED_CHECKS - 1, "T17: all expected 032 checks executed")
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("[032] PASS %s" % label)
	else:
		_failed += 1
		print("[032] FAIL %s" % label)


func _finish() -> void:
	print("[032] CHECKS=%d FAILURES=%d" % [_passed, _failed])
	if _failed == 0:
		print("ALL_032_CHECKS_PASSED")
	get_tree().quit(0)


## --- Fixtures ---------------------------------------------------------------

func _instance(id: String, mood: int = 50) -> NpcInstance:
	var instance := NpcInstance.new()
	instance.instance_id = id
	instance.template_id = "char:test"
	instance.display_name = id
	instance.mood = mood
	return instance


func _map(include_hangouts: bool = true) -> Map:
	var map := Map.new()
	map.id = "map:032_test"
	map.spawn_point = Vector2(10, 10)
	if include_hangouts:
		map.markers = {
			"hangout_cafeteria": Vector2(40, 40),
			"hangout_courtyard": Vector2(50, 50),
			"hangout_garden": Vector2(60, 60),
			"hangout_library": Vector2(70, 70),
			"classroom_a": Vector2(5, 5),
		}
		map.hangout_interests = {
			"hangout_cafeteria": PackedStringArray(["social", "food"]),
			"hangout_courtyard": PackedStringArray(["sports", "active", "social"]),
			"hangout_garden": PackedStringArray(["quiet", "nature", "calm"]),
			"hangout_library": PackedStringArray(["academic", "study", "quiet"]),
		}
	return map


func _single_map() -> Map:
	var map := Map.new()
	map.id = "map:032_single"
	map.markers = {"hangout_only": Vector2(88, 99)}
	return map


func _meter(from_instance: NpcInstance, to_instance: NpcInstance, familiarity: int, affection: int) -> void:
	from_instance.meters[to_instance.instance_id] = {
		"familiarity": familiarity,
		"affection": affection,
	}


## Dynamic call keeps the harness parseable before the 6th argument exists, so
## RED shows individual check failures rather than a script-load error.
func _select(
	instance: NpcInstance,
	template: CharacterTemplate,
	map: Map,
	seed_value: int,
	eval_count: int,
	roster: Array
) -> Dictionary:
	var ai_script: Script = load("res://scripts/NpcAi.gd") as Script
	var result: Variant = ai_script.callv(
		"select_goal", [instance, template, map, seed_value, eval_count, roster]
	)
	if result is Dictionary:
		return result as Dictionary
	return {}


func _goal_counts(instance: NpcInstance, template: CharacterTemplate, map: Map, roster: Array) -> Dictionary:
	var counts: Dictionary = {}
	for i in range(SAMPLES):
		var result: Dictionary = _select(instance, template, map, i * 7919 + 17, i, roster)
		var goal: String = str(result.get("goal", ""))
		counts[goal] = int(counts.get(goal, 0)) + 1
	return counts


## --- T1-T5: pure classification --------------------------------------------

func _empty_candidates() -> bool:
	var instance := _instance("npc:self")
	return (
		NpcAi.relationship_candidates(null, []).is_empty()
		and NpcAi.relationship_candidates(instance, []).is_empty()
		and NpcAi.relationship_candidates(instance, [instance]).is_empty()
	)


func _classified(expected: String, familiar: int, affection: int, expected_weight: int) -> bool:
	var instance := _instance("npc:self")
	var other := _instance("npc:other")
	_meter(instance, other, familiar, affection)
	var candidates: Array = NpcAi.relationship_candidates(instance, [other])
	if candidates.size() != 1:
		return false
	var candidate: Dictionary = candidates[0] as Dictionary
	return (
		str(candidate.get("relationship", "")) == expected
		and int(candidate.get("weight", 0)) == expected_weight
		and str(candidate.get("id", "")) == other.instance_id
	)


func _weak_and_malformed_meters() -> bool:
	var instance := _instance("npc:self")
	var stranger := _instance("npc:stranger")
	var acquaintance := _instance("npc:acquaintance")
	var malformed := _instance("npc:malformed")
	var null_entry: Variant = null
	_meter(instance, stranger, 5, 5)
	_meter(instance, acquaintance, 25, 5)
	instance.meters[malformed.instance_id] = "not a meter"
	var candidates: Array = NpcAi.relationship_candidates(
		instance, [stranger, acquaintance, malformed, null_entry, "not an instance"]
	)
	return candidates.is_empty()


## --- T6-T11: seek / avoid ---------------------------------------------------

func _seek_distribution(kind: String, familiar: int, affection: int, target_goal: String) -> bool:
	var instance := _instance("npc:self")
	var template: CharacterTemplate = CharacterTemplate.new()
	var map := _map()
	var candidate := _instance("npc:friend")
	candidate.current_goal = target_goal
	_meter(instance, candidate, familiar, affection)

	var baseline: Dictionary = _goal_counts(instance, template, map, [])
	var boosted: Dictionary = _goal_counts(instance, template, map, [candidate])
	var target_base: int = int(baseline.get(target_goal, 0))
	var target_boosted: int = int(boosted.get(target_goal, 0))
	if target_boosted <= target_base:
		return false
	for key in boosted.keys():
		if str(key) != target_goal and int(boosted[key]) >= target_boosted:
			return false
	return true


func _avoid_hangout() -> bool:
	var instance := _instance("npc:self")
	var template: CharacterTemplate = CharacterTemplate.new()
	var map := _map()
	var enemy := _instance("npc:enemy")
	enemy.current_goal = "hangout:library"
	_meter(instance, enemy, 0, -25)
	var counts: Dictionary = _goal_counts(instance, template, map, [enemy])
	return int(counts.get("hangout:library", 0)) == 0 and int(counts.get("", 0)) == 0


func _degenerate_all_enemy() -> bool:
	var instance := _instance("npc:self")
	var enemy := _instance("npc:enemy")
	enemy.current_goal = "hangout_only"
	_meter(instance, enemy, 0, -25)
	var result: Dictionary = _select(instance, CharacterTemplate.new(), _single_map(), 3, 1, [enemy])
	var destination: Variant = result.get("destination", null)
	return (
		str(result.get("goal", "")) == "hangout:hangout_only"
		and destination is Vector2
		and (destination as Vector2) == Vector2(88, 99)
	)


func _seek_player() -> bool:
	var instance := _instance("npc:self")
	var player := _instance("player")
	player.position = Vector2(321, 77)
	_meter(instance, player, 65, 65)
	var map := _map(false)
	for i in range(8):
		var result: Dictionary = _select(instance, CharacterTemplate.new(), map, i + 1, i, [player])
		var destination: Variant = result.get("destination", null)
		if str(result.get("goal", "")) != "seek:player" or destination != Vector2(321, 77):
			return false
	return true


func _avoid_player() -> bool:
	var instance := _instance("npc:self")
	var player := _instance("player")
	player.position = Vector2(321, 77)
	_meter(instance, player, 0, -25)
	var counts: Dictionary = _goal_counts(instance, CharacterTemplate.new(), _map(), [player])
	return (
		int(counts.get("avoid:player", 0)) == 0
		and int(counts.get("seek:player", 0)) == 0
	)


## --- T12-T15: regressions and robustness ------------------------------------

func _quiet_count(mood: int) -> int:
	var instance := _instance("npc:self", mood)
	var counts: Dictionary = _goal_counts(instance, CharacterTemplate.new(), _map(), [])
	return int(counts.get("hangout:hangout_library", 0)) + int(counts.get("hangout:hangout_garden", 0))


func _v1_mood_path_preserved() -> bool:
	return _quiet_count(20) > _quiet_count(80)


func _deterministic() -> bool:
	var instance := _instance("npc:self")
	var friend := _instance("npc:friend")
	friend.current_goal = "hangout:library"
	_meter(instance, friend, 25, 25)
	var roster: Array = [friend]
	var map := _map()
	var template: CharacterTemplate = CharacterTemplate.new()
	var first: Dictionary = _select(instance, template, map, 1234, 7, roster)
	var second: Dictionary = _select(instance, template, map, 1234, 7, roster)
	return (
		not first.is_empty()
		and str(first.get("goal", "")) == str(second.get("goal", ""))
		and str(first.get("destination", "")) == str(second.get("destination", ""))
	)


func _stale_marker_fallback() -> bool:
	var instance := _instance("npc:self")
	var friend := _instance("npc:friend")
	friend.current_goal = "hangout:does_not_exist"
	_meter(instance, friend, 25, 25)
	var map := _map()
	var names: Array = map.get_hangout_marker_names()
	var result: Dictionary = _select(instance, CharacterTemplate.new(), map, 9, 2, [friend])
	var goal: String = str(result.get("goal", ""))
	if not goal.begins_with("hangout:"):
		return false
	return names.has(goal.substr("hangout:".length()))


func _defensive_roster() -> bool:
	var instance := _instance("npc:self")
	var friend := _instance("npc:friend")
	friend.current_goal = "hangout:library"
	_meter(instance, friend, 25, 25)
	var roster: Array = [null, "not an instance", instance, friend, friend]
	var candidates: Array = NpcAi.relationship_candidates(instance, roster)
	if candidates.size() != 1:
		return false
	return str((candidates[0] as Dictionary).get("id", "")) == friend.instance_id


## --- T16: scene-side wiring -------------------------------------------------

func _node_wiring() -> bool:
	var instance := _instance("npc:self")
	var friend := _instance("npc:friend")
	friend.current_goal = "hangout_only"
	_meter(instance, friend, 65, 65)

	var npc := Npc.new()
	if not npc.has_method("set_relationship_roster"):
		return false
	add_child(npc)
	npc.setup(instance)
	npc.call("set_relationship_roster", [friend])
	npc.set_ai_enabled(true, _single_map(), 7)
	var ok: bool = (
		instance.current_goal == "hangout:hangout_only"
		and instance.goal_destination == Vector2(88, 99)
	)
	npc.free()
	return ok
