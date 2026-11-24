## TraitsAndDialogueContentTest
##
## Persistent headless acceptance harness for ticket 022. It checks the authored
## base content at the seams a modder or the conversation pipeline actually uses:
## resource files load through ModLoader, ids stay add-only unique, every topic
## has an authored default response, greetings cover all four variation factors,
## and the default player/NPC pair still finds an eligible greeting and response.
## Prints ALL_022_CHECKS_PASSED only when every assertion passed.
extends Node


## --- Fixture paths ----------------------------------------------------------

const TRAITS_DIR: String = "res://resources/traits/"
const TOPICS_DIR: String = "res://resources/dialogue/"
const GREETINGS_DIR: String = "res://resources/dialogue/greetings/"
const RESPONSES_DIR: String = "res://resources/dialogue/responses/"

const EXPECTED_TRAITS: int = 24
const EXPECTED_GREETINGS: int = 12
const EXPECTED_TOPICS: int = 16
const EXPECTED_RESPONSES: int = 27
const EXPECTED_CHECKS: int = 23

const STATS: Array[String] = ["strength", "dexterity", "constitution", "intelligence", "wisdom", "charisma"]
const CATEGORIES: Array[String] = ["skill", "interest", "dislike", "personality"]
const PERIODS: Array[String] = ["PERIOD1", "PERIOD2", "PERIOD3", "PERIOD4", "FREETIME1", "FREETIME2", "FREETIME3"]

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var traits: Array = _load_dir(TRAITS_DIR)
	var greetings: Array = _load_dir(GREETINGS_DIR)
	var topics: Array = _load_dir(TOPICS_DIR)
	var responses: Array = _load_dir(RESPONSES_DIR)

	_check(_count_files(TRAITS_DIR) == EXPECTED_TRAITS, "T1: 24 authored trait .tres files")
	_check(_count_files(GREETINGS_DIR) == EXPECTED_GREETINGS, "T2: 12 authored greeting .tres files")
	_check(_count_files(TOPICS_DIR) == EXPECTED_TOPICS, "T3: 16 authored player-topic .tres files")
	_check(_count_files(RESPONSES_DIR) == EXPECTED_RESPONSES, "T4: 27 authored response .tres files")
	var dialogue_total: int = greetings.size() + topics.size() + responses.size()
	_check(dialogue_total >= 40 and dialogue_total <= 60, "T5: %d dialogue resources are in the 40-60 range" % dialogue_total)

	_check(_categories_covered(traits), "T6: all four trait categories are authored")
	_check(_traits_well_formed(traits), "T7: every trait has a name, category and tags")
	_check(_ids_unique(_ids(traits)), "T8: authored trait ids are unique")
	_check(_default_responses_cover_topics(topics, responses), "T9: every topic has a line-only authored default response")
	_check(_has_generic_response(responses), "T10: a generic authored fallback response exists")
	_check(_specific_responses_exist(responses), "T11: exact-match outcome/band responses exist")
	_check(_bands_valid_and_covered(greetings, responses), "T12: relationship bands are valid and all five are greeted")
	_check(_periods_valid_and_covered(greetings), "T13: periods use TimeManager names and all seven are covered")
	_check(_mood_gates_covered(greetings), "T14: mood gates cover low and high moods within 0-100")
	_check(_gate_references_resolve(traits, greetings, topics), "T15: trait/interest gates reference authored trait ids or tags")
	_check(_stats_valid(topics, responses), "T16: rollable content uses only the six authored stat names")
	_check(_all_ids_unique(traits, greetings, topics, responses), "T17: all authored content ids are unique")
	_check(_add_only_still_enforced(), "T18: duplicate ids are rejected in all four buckets")
	_check(_smoke_greeting(), "T19: default player/NPC pair has an eligible authored greeting")
	_check(_smoke_response(topics), "T20: default player/NPC pair has an eligible base topic with a default response")
	_check(_files_load_and_register(traits, greetings, topics, responses), "T21: every authored file loads and registers in its bucket")
	_check(_rollable_replies_exist(responses), "T22: rollable reply options exist for several topics")
	_check(_passed == EXPECTED_CHECKS - 1, "T23: all expected 022 checks executed")
	_finish()


## --- File loading -----------------------------------------------------------

func _count_files(dir_path: String) -> int:
	var count: int = 0
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.ends_with(".tres"):
			count += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return count


func _load_dir(dir_path: String) -> Array:
	var resources: Array = []
	for path in _paths(dir_path):
		var resource: Resource = ResourceLoader.load(path)
		if resource != null:
			resources.append(resource)
	return resources


func _paths(dir_path: String) -> Array[String]:
	var paths: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.ends_with(".tres"):
			paths.append(dir_path + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


func _ids(resources: Array) -> Array[String]:
	var ids: Array[String] = []
	for item in resources:
		var id: String = str(item.get("id"))
		if not id.is_empty():
			ids.append(id)
	return ids


func _ids_unique(ids: Array) -> bool:
	var seen: Dictionary = {}
	for id in ids:
		if seen.has(id):
			return false
		seen[id] = true
	return not ids.is_empty()


func _all_ids_unique(traits: Array, greetings: Array, topics: Array, responses: Array) -> bool:
	return _ids_unique(_ids(traits) + _ids(greetings) + _ids(topics) + _ids(responses))


## A malformed .tres would still be counted by _count_files(), so assert the
## loaded resource count matches the file count and every id reaches its bucket.
func _files_load_and_register(traits: Array, greetings: Array, topics: Array, responses: Array) -> bool:
	if (
		traits.size() != EXPECTED_TRAITS
		or greetings.size() != EXPECTED_GREETINGS
		or topics.size() != EXPECTED_TOPICS
		or responses.size() != EXPECTED_RESPONSES
	):
		return false
	var pairs: Array = [
		[traits, ModLoader.TYPE_TRAIT],
		[greetings, ModLoader.TYPE_GREETING],
		[topics, ModLoader.TYPE_DIALOGUE],
		[responses, ModLoader.TYPE_RESPONSE],
	]
	for pair in pairs:
		var bucket: String = str(pair[1])
		for item in pair[0]:
			if not ModLoader.has_resource(bucket, str(item.get("id"))):
				print("[022] authored id '%s' missing from bucket '%s'" % [str(item.get("id")), bucket])
				return false
	return true


## --- Content shape checks ---------------------------------------------------

func _categories_covered(traits: Array) -> bool:
	for category in CATEGORIES:
		var count: int = 0
		for item in traits:
			if str(item.get("category")) == category:
				count += 1
		if count < 4:
			print("[022] category '%s' has only %d traits" % [category, count])
			return false
	return true


func _traits_well_formed(traits: Array) -> bool:
	for item in traits:
		var trait_resource: Trait = item as Trait
		if trait_resource == null:
			return false
		if trait_resource.id.is_empty() or trait_resource.display_name.is_empty():
			return false
		if not CATEGORIES.has(trait_resource.category):
			return false
		# Trait.gd permits point_cost = 0, so only the tag list is required here.
		if trait_resource.tags.is_empty():
			return false
	return true


func _default_responses_cover_topics(topics: Array, responses: Array) -> bool:
	for item in topics:
		var topic: DialogueTopic = item as DialogueTopic
		if topic == null:
			return false
		var defaults: int = 0
		for candidate in responses:
			var response: DialogueResponse = candidate as DialogueResponse
			if (
				response != null
				and response.topic_id == topic.id
				and response.outcomes.is_empty()
				and response.relationship_bands.is_empty()
				and response.is_line_only()
			):
				defaults += 1
		if defaults == 0:
			print("[022] topic '%s' has no authored default response" % topic.id)
			return false
	return true


func _has_generic_response(responses: Array) -> bool:
	for item in responses:
		var response: DialogueResponse = item as DialogueResponse
		if (
			response != null
			and response.topic_id.is_empty()
			and response.outcomes.is_empty()
			and response.relationship_bands.is_empty()
			and response.is_line_only()
		):
			return true
	return false


func _specific_responses_exist(responses: Array) -> bool:
	var count: int = 0
	for item in responses:
		var response: DialogueResponse = item as DialogueResponse
		if response != null and not response.outcomes.is_empty() and not response.relationship_bands.is_empty():
			count += 1
	return count >= 6


## The NPC-initiated reply flow needs rollable lines with their own deltas.
## Empty outcome/band keys make them topic-level reply options rather than
## exact-match reactions; is_line_only() keeps them distinct from topic defaults.
func _rollable_replies_exist(responses: Array) -> bool:
	var topics: Dictionary = {}
	for item in responses:
		var response: DialogueResponse = item as DialogueResponse
		if (
			response != null
			and not response.is_line_only()
			and not response.topic_id.is_empty()
			and response.outcomes.is_empty()
			and response.relationship_bands.is_empty()
		):
			topics[response.topic_id] = true
	return topics.size() >= 3


func _valid_bands() -> Array[String]:
	return [
		DialogueResolver.TYPE_STRANGER, DialogueResolver.TYPE_ACQUAINTANCE,
		DialogueResolver.TYPE_FRIEND, DialogueResolver.TYPE_ENEMY, DialogueResolver.TYPE_LOVER,
	]


func _bands_valid_and_covered(greetings: Array, responses: Array) -> bool:
	var valid: Array[String] = _valid_bands()
	var covered: Dictionary = {}
	for item in greetings:
		var greeting: DialogueGreeting = item as DialogueGreeting
		if greeting == null:
			return false
		for band in greeting.relationship_types:
			if not valid.has(band):
				return false
			covered[band] = true
	for item in responses:
		var response: DialogueResponse = item as DialogueResponse
		if response == null:
			return false
		for band in response.relationship_bands:
			if not valid.has(band):
				return false
	for band in valid:
		if not covered.has(band):
			print("[022] no greeting covers band '%s'" % band)
			return false
	return true


func _periods_valid_and_covered(greetings: Array) -> bool:
	var valid: Array = TimeManager.DayState.keys()
	var covered: Dictionary = {}
	for item in greetings:
		var greeting: DialogueGreeting = item as DialogueGreeting
		if greeting == null:
			return false
		for period in greeting.periods:
			if not valid.has(period):
				print("[022] unknown period '%s'" % period)
				return false
			covered[period] = true
	for period in PERIODS:
		if not covered.has(period):
			print("[022] no greeting covers period '%s'" % period)
			return false
	return true


func _mood_gates_covered(greetings: Array) -> bool:
	var has_min: bool = false
	var has_max: bool = false
	for item in greetings:
		var greeting: DialogueGreeting = item as DialogueGreeting
		if greeting == null:
			return false
		if greeting.min_mood < 0 or greeting.max_mood > 100 or greeting.min_mood > greeting.max_mood:
			return false
		if greeting.min_mood > 0:
			has_min = true
		if greeting.max_mood < 100:
			has_max = true
	return has_min and has_max


func _gate_references_resolve(traits: Array, greetings: Array, topics: Array) -> bool:
	var known: Dictionary = {}
	for item in traits:
		var trait_resource: Trait = item as Trait
		known[trait_resource.id] = true
		for tag in trait_resource.tags:
			known[str(tag)] = true
	for item in greetings:
		var greeting: DialogueGreeting = item as DialogueGreeting
		if not _known_keys(greeting.required_traits, known) or not _known_keys(greeting.required_interests, known):
			return false
	for item in topics:
		var topic: DialogueTopic = item as DialogueTopic
		if not _known_keys(topic.required_traits, known) or not _known_keys(topic.required_interests, known):
			return false
	return true


func _known_keys(values: PackedStringArray, known: Dictionary) -> bool:
	for value in values:
		if not value.is_empty() and not known.has(value):
			print("[022] gate references unknown trait/tag '%s'" % value)
			return false
	return true


func _stats_valid(topics: Array, responses: Array) -> bool:
	for item in topics:
		var topic: DialogueTopic = item as DialogueTopic
		if topic == null or (not topic.checked_stat.is_empty() and not STATS.has(topic.checked_stat)):
			return false
		if topic.difficulty < 0:
			return false
	for item in responses:
		var response: DialogueResponse = item as DialogueResponse
		if response == null:
			return false
		if not response.is_line_only() and not STATS.has(response.checked_stat):
			return false
	return true


func _add_only_still_enforced() -> bool:
	var duplicate_trait := Trait.new()
	duplicate_trait.id = "trait:studious"
	var duplicate_greeting := DialogueGreeting.new()
	duplicate_greeting.id = "greeting:generic"
	var duplicate_topic := DialogueTopic.new()
	duplicate_topic.id = "topic:ask_day"
	var duplicate_response := DialogueResponse.new()
	duplicate_response.id = "response:generic"
	return (
		not ModLoader.register_resource(ModLoader.TYPE_TRAIT, duplicate_trait, "022_test")
		and not ModLoader.register_resource(ModLoader.TYPE_GREETING, duplicate_greeting, "022_test")
		and not ModLoader.register_resource(ModLoader.TYPE_DIALOGUE, duplicate_topic, "022_test")
		and not ModLoader.register_resource(ModLoader.TYPE_RESPONSE, duplicate_response, "022_test")
	)


## --- Default-pair smoke checks ----------------------------------------------

func _default_pair() -> Dictionary:
	var player_template := ModLoader.get_resource(ModLoader.TYPE_CHARACTER, "char:alex") as CharacterTemplate
	var npc_template := ModLoader.get_resource(ModLoader.TYPE_CHARACTER, "char:jordan") as CharacterTemplate
	var player := NpcInstance.from_template(player_template, "player")
	var npc := NpcInstance.from_template(npc_template, "npc:jordan")
	player.mood = 50
	npc.mood = 50
	var keys: Array[String] = DialogueFilter.trait_keys(player_template)
	keys.append_array(DialogueFilter.trait_keys(npc_template))
	return {
		"player": player,
		"npc": npc,
		"player_template": player_template,
		"npc_template": npc_template,
		"keys": keys,
	}


func _smoke_greeting() -> bool:
	var pair: Dictionary = _default_pair()
	var player: NpcInstance = pair["player"]
	var npc: NpcInstance = pair["npc"]
	var player_template: CharacterTemplate = pair["player_template"]
	var npc_template: CharacterTemplate = pair["npc_template"]
	var keys: Array[String] = pair["keys"]
	# Greetings are spoken by the NPC, so the band is the NPC's relationship
	# toward the player (the spoken-line rule in idea-v2-brainstorming.md:78).
	var band: String = DialogueResolver.relationship_type(npc, player, npc_template, player_template)
	var period: String = str(TimeManager.DayState.keys()[TimeManager.DayState.PERIOD1])
	var eligible: int = 0
	for item in ModLoader.get_all(ModLoader.TYPE_GREETING):
		var greeting: DialogueGreeting = item as DialogueGreeting
		if _greeting_eligible(greeting, band, player.mood, period, keys):
			eligible += 1
	print("[022] default pair: band=%s period=%s eligible greetings=%d" % [band, period, eligible])
	return eligible > 0


## Mirrors the 021 DialogueGreeting eligibility contract until 023 owns selection.
func _greeting_eligible(
	greeting: DialogueGreeting,
	band: String,
	mood: int,
	period: String,
	keys: Array[String]
) -> bool:
	if greeting == null or greeting.text.is_empty():
		return false
	if not greeting.relationship_types.is_empty() and not greeting.relationship_types.has(band):
		return false
	if greeting.min_mood > 0 and mood < greeting.min_mood:
		return false
	if greeting.max_mood < 100 and mood > greeting.max_mood:
		return false
	if not greeting.periods.is_empty() and not greeting.periods.has(period):
		return false
	for id in greeting.required_traits:
		if not id.is_empty() and not keys.has(id):
			return false
	for id in greeting.required_interests:
		if not id.is_empty() and not keys.has(id):
			return false
	return true


func _smoke_response(base_topics: Array) -> bool:
	var pair: Dictionary = _default_pair()
	var player: NpcInstance = pair["player"]
	var npc: NpcInstance = pair["npc"]
	var player_template: CharacterTemplate = pair["player_template"]
	var npc_template: CharacterTemplate = pair["npc_template"]
	# Only 022's authored base topics are in scope; a mod may add topics without
	# a default response and must not make this base-content check look incomplete.
	var base_ids: Dictionary = {}
	for item in base_topics:
		base_ids[str(item.get("id"))] = true
	var eligible_topics: int = 0
	var answered: int = 0
	for item in ModLoader.get_all(ModLoader.TYPE_DIALOGUE):
		var topic: DialogueTopic = item as DialogueTopic
		if (
			topic == null
			or not base_ids.has(topic.id)
			or not DialogueFilter.is_eligible(topic, player, npc, player_template, npc_template)
		):
			continue
		eligible_topics += 1
		for candidate in ModLoader.get_all(ModLoader.TYPE_RESPONSE):
			var response: DialogueResponse = candidate as DialogueResponse
			if (
				response != null
				and response.topic_id == topic.id
				and response.outcomes.is_empty()
				and response.relationship_bands.is_empty()
				and not response.text.is_empty()
			):
				answered += 1
				break
	print("[022] default pair: eligible topics=%d answered=%d" % [eligible_topics, answered])
	return eligible_topics > 0 and answered > 0


## --- Assertion / completion -------------------------------------------------

func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("[022] PASS " + label)
	else:
		_failed += 1
		print("[022] FAIL " + label)


func _finish() -> void:
	print("[022] RESULT passed=%d failed=%d" % [_passed, _failed])
	if _failed == 0:
		print("ALL_022_CHECKS_PASSED")
	else:
		print("SOME_022_CHECKS_FAILED")
	get_tree().quit(0 if _failed == 0 else 1)
