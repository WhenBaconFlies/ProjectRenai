## ConversationHelperTest
##
## Persistent headless acceptance harness for ticket 023. It drives the pure
## Conversation helper and the extended DialogueFilter/DialogueResolver seams at
## the boundaries ticket 024 will use: phase/turn rules, greeting factors and
## fallbacks, the layered response chain, response rolls vs line-only reactions,
## relationship banding, both-party deltas, the NPC-initiated shape, and seeded
## determinism. Prints ALL_023_CHECKS_PASSED only when every assertion passed.
extends Node


const EXPECTED_CHECKS: int = 35

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(_global_class_registered(), "T1: Conversation is registered as a global class")
	_check(_source_is_pure(), "T2: Conversation source has no scene-tree or autoload references")
	_check(_instantiable(), "T3: Conversation is headless-instantiable and starts closed at GREETING")

	_check_determinism()
	_check_phase_flow()
	_check_greeting_factors()
	_check_greeting_fallbacks()
	_check_response_fallbacks()
	_check_resolution()
	_check_relationship_band()
	_check_npc_initiated()
	_check_conversation_fallbacks()
	_check_full_flow()

	_check(_passed == EXPECTED_CHECKS - 1, "T35: all expected 023 checks executed")
	_finish()


## --- T1-T3: purity / instantiation -----------------------------------------

func _global_class_registered() -> bool:
	for entry in ProjectSettings.get_global_class_list():
		if str((entry as Dictionary).get("class", "")) == "Conversation":
			return true
	return false


func _source_is_pure() -> bool:
	var file: FileAccess = FileAccess.open("res://scripts/Conversation.gd", FileAccess.READ)
	if file == null:
		return false
	var source: String = file.get_as_text()
	file.close()
	var forbidden: Array[String] = [
		"get_tree()", "get_node(", "ModLoader.", "TimeManager.",
		"GameManager.", "Engine.get_main_loop",
	]
	for token in forbidden:
		if source.contains(token):
			print("[023] impure Conversation source contains '%s'" % token)
			return false
	return true


func _instantiable() -> bool:
	var conversation := Conversation.new()
	return (
		conversation != null
		and not conversation.is_open()
		and conversation.is_done() == false
		and conversation.get_phase() == Conversation.Phase.GREETING
		and conversation.get_turn() == 0
	)


## --- T4: seeded determinism -------------------------------------------------

func _check_determinism() -> void:
	var greetings: Array = [_greeting("greeting:a", "A"), _greeting("greeting:b", "B")]
	var first := _started_player_conversation(1234)
	var second := _started_player_conversation(1234)
	var a: Dictionary = first["conversation"].choose_greeting(greetings)
	var b: Dictionary = second["conversation"].choose_greeting(greetings)
	_check(
		a.get("id") == b.get("id") and a.get("text") == b.get("text") and a.get("fallback") == b.get("fallback"),
		"T4: the same seed selects the same authored greeting"
	)


## --- T5-T7: phase flow and turn limits -------------------------------------

func _check_phase_flow() -> void:
	var pair: Dictionary = _fresh_pair()
	var conversation := Conversation.new()
	conversation.begin_player_initiated(
		pair["player"], pair["npc"], pair["pt"], pair["nt"], 77, "PERIOD1"
	)
	_check(
		conversation.is_open() and conversation.get_phase() == Conversation.Phase.GREETING
		and conversation.get_initiator_id() == "player" and conversation.get_target_id() == "npc:jordan"
		and not conversation.can_pick_topic(),
		"T5: begin sets ids, opens at GREETING and blocks topic picks"
	)

	conversation.choose_greeting([_greeting("greeting:any", "Hi")])
	_check(
		conversation.get_phase() == Conversation.Phase.TOPIC and conversation.can_pick_topic(),
		"T6: choosing a greeting opens the TOPIC phase"
	)

	var topic: DialogueTopic = _topic("topic:one", "charisma", 0)
	var roll: Dictionary = conversation.choose_topic(topic)
	_check(
		not roll.is_empty() and conversation.get_turn() == 1
		and conversation.get_phase() == Conversation.Phase.RESPONSE
		and not conversation.can_pick_topic(),
		"T7: first pick rolls, counts one turn and blocks a pick during RESPONSE"
	)

	conversation.select_response([_response("response:one", "Reply one", "topic:one", [], [])], [topic])
	_check(
		conversation.get_phase() == Conversation.Phase.FOLLOWUP and conversation.can_pick_topic(),
		"T8: the first response opens the optional FOLLOWUP pick"
	)

	var second_topic: DialogueTopic = _topic("topic:two", "charisma", 0)
	conversation.choose_topic(second_topic)
	conversation.select_response(
		[_response("response:two", "Reply two", "topic:two", [], [])], [second_topic]
	)
	_check(
		conversation.get_phase() == Conversation.Phase.DONE and conversation.is_done()
		and not conversation.is_open() and conversation.get_turn() == 2,
		"T9: the second response ends the conversation after exactly two picks"
	)

	var extra: Dictionary = conversation.choose_topic(_topic("topic:three", "charisma", 0))
	_check(
		extra.is_empty() and conversation.get_turn() == 2 and conversation.get_phase() == Conversation.Phase.DONE,
		"T10: a third pick is rejected and the turn count stays at two"
	)

	var early := _started_player_conversation(9)
	early["conversation"].choose_greeting([_greeting("greeting:any", "Hi")])
	early["conversation"].leave()
	_check(
		early["conversation"].is_done() and not early["conversation"].is_open(),
		"T11: leave() closes the conversation early"
	)


## --- T12-T15: greeting factors and any-eligible fallback --------------------

func _check_greeting_factors() -> void:
	var pair: Dictionary = _fresh_pair()
	var player: NpcInstance = pair["player"]
	var npc: NpcInstance = pair["npc"]
	var keys: Array[String] = DialogueFilter.trait_keys(pair["pt"])
	keys.append_array(DialogueFilter.trait_keys(pair["nt"]))
	var stranger: String = DialogueResolver.relationship_type(npc, player, pair["nt"], pair["pt"])

	var band_gate: DialogueGreeting = _greeting("g:band", "band")
	band_gate.relationship_types = PackedStringArray(["Lover"])
	_check(
		not DialogueFilter.is_greeting_eligible(band_gate, stranger, 50, "PERIOD1", keys),
		"T12: greeting relationship-type gate rejects a mismatched band"
	)

	var mood_gate: DialogueGreeting = _greeting("g:mood", "mood")
	mood_gate.min_mood = 70
	mood_gate.max_mood = 90
	_check(
		not DialogueFilter.is_greeting_eligible(mood_gate, stranger, 50, "PERIOD1", keys)
		and DialogueFilter.is_greeting_eligible(mood_gate, stranger, 80, "PERIOD1", keys),
		"T13: greeting mood band gate rejects low and high moods"
	)

	var period_gate: DialogueGreeting = _greeting("g:period", "period")
	period_gate.periods = PackedStringArray(["FREETIME2"])
	_check(
		not DialogueFilter.is_greeting_eligible(period_gate, stranger, 50, "PERIOD1", keys)
		and DialogueFilter.is_greeting_eligible(period_gate, stranger, 50, "FREETIME2", keys),
		"T14: greeting period gate uses TimeManager state names"
	)

	var trait_gate: DialogueGreeting = _greeting("g:trait", "trait")
	trait_gate.required_traits = PackedStringArray(["trait:__missing__"])
	trait_gate.required_interests = PackedStringArray(["interest:__missing__"])
	_check(
		not DialogueFilter.is_greeting_eligible(trait_gate, stranger, 50, "PERIOD1", keys),
		"T15: greeting trait/interest gates reject missing tags"
	)


func _check_greeting_fallbacks() -> void:
	var impossible: DialogueGreeting = _greeting("g:impossible", "Any greeting")
	impossible.relationship_types = PackedStringArray(["Lover"])
	impossible.periods = PackedStringArray(["NO_SUCH_PERIOD"])
	impossible.required_traits = PackedStringArray(["trait:__missing__"])
	var relaxed: Dictionary = DialogueFilter.select_greeting([impossible], "Stranger", 50, "PERIOD1", [], 5)
	_check(
		relaxed.get("fallback", "") == "any_eligible" and relaxed.get("text", "") == "Any greeting",
		"T16: no factor match falls back to any authored greeting"
	)

	var generated: Dictionary = DialogueFilter.select_greeting([], "Stranger", 50, "PERIOD1", [], 5)
	_check(
		generated.get("fallback", "") == "generated" and not str(generated.get("text", "")).is_empty(),
		"T17: no greetings at all still yields a generated opening line"
	)


## --- T18-T21: layered response fallback ------------------------------------

func _check_response_fallbacks() -> void:
	var exact: DialogueResponse = _response("r:exact", "exact", "topic:t", ["success"], ["Friend"])
	var exact_result: Dictionary = DialogueFilter.select_response([exact], "topic:t", "success", "Friend", 1)
	_check(exact_result.get("fallback", "") == "exact", "T18: exact topic+outcome+band layer wins")

	var default: DialogueResponse = _response("r:default", "default", "topic:t", [], [])
	var default_result: Dictionary = DialogueFilter.select_response([default], "topic:t", "success", "Enemy", 1)
	_check(default_result.get("fallback", "") == "topic_default", "T19: topic default is used when no exact line exists")

	var partial: DialogueResponse = _response("r:partial", "partial", "topic:t", ["failure"], [])
	var partial_result: Dictionary = DialogueFilter.select_response([partial], "topic:t", "failure", "Stranger", 1)
	_check(partial_result.get("fallback", "") == "topic_partial", "T20: partial topic match beats the generic line")

	var generic: DialogueResponse = _response("r:generic", "generic", "", [], [])
	var generic_result: Dictionary = DialogueFilter.select_response([generic], "topic:t", "success", "Stranger", 1)
	var generated_result: Dictionary = DialogueFilter.select_response([], "topic:t", "success", "Stranger", 1)
	_check(
		generic_result.get("fallback", "") == "generic_authored"
		and generated_result.get("fallback", "") == "generated"
		and not str(generated_result.get("text", "")).is_empty(),
		"T21: generic authored line and generated last resort never dead-end"
	)


## --- T22-T24: response resolution / line-only -------------------------------

func _check_resolution() -> void:
	var pair: Dictionary = _fresh_pair()
	var player: NpcInstance = pair["player"]
	var npc: NpcInstance = pair["npc"]
	var topic: DialogueTopic = _topic_with_modifier("topic:mod", "charisma", 0)
	var rollable: DialogueResponse = _roll_response("r:roll", "Rolled line", "topic:mod", "charisma", 0)
	var result: Dictionary = DialogueResolver.resolve_response(
		rollable, player, npc, pair["pt"], pair["nt"], [topic], 42
	)

	var before: Dictionary = result.get("before", {})
	var after: Dictionary = result.get("after", {})
	var deltas: Dictionary = result.get("deltas", {})
	var initiator_delta: Dictionary = deltas.get("initiator", {})
	var target_delta: Dictionary = deltas.get("target", {})
	var initiator_before: Dictionary = before.get("initiator", {})
	var initiator_after: Dictionary = after.get("initiator", {})
	var target_before: Dictionary = before.get("target", {})
	var target_after: Dictionary = after.get("target", {})
	_check(
		not result.is_empty() and not bool(result.get("line_only", true))
		and int(initiator_delta.get("affection", 0)) > 0
		and int(target_delta.get("affection", 0)) > 0
		and int(initiator_after.get("affection", 0)) - int(initiator_before.get("affection", 0)) == int(initiator_delta.get("affection", 0))
		and int(target_after.get("affection", 0)) - int(target_before.get("affection", 0)) == int(target_delta.get("affection", 0)),
		"T22: resolve_response rolls with response-owned fields and writes both parties' meters"
	)

	var plain_result: Dictionary = DialogueResolver.resolve_response(
		rollable, player, npc, pair["pt"], pair["nt"], [], 42
	)
	_check(
		int(result.get("effective_difficulty", 0)) == int(plain_result.get("effective_difficulty", 0)) + 5,
		"T23: recipient modifiers from the keyed topic are reused"
	)

	var fresh: Dictionary = _fresh_pair()
	var line_only: DialogueResponse = _roll_response("r:line", "Line only", "topic:mod", "", 99)
	line_only.affection_delta_success = 25
	var line_result: Dictionary = DialogueResolver.resolve_response(
		line_only, fresh["player"], fresh["npc"], fresh["pt"], fresh["nt"], [topic], 42
	)
	var line_before: Dictionary = line_result.get("before", {})
	var line_after: Dictionary = line_result.get("after", {})
	var line_deltas: Dictionary = line_result.get("deltas", {})
	var line_initiator_delta: Dictionary = line_deltas.get("initiator", {})
	var line_target_delta: Dictionary = line_deltas.get("target", {})
	_check(
		bool(line_result.get("line_only", false))
		and not bool(line_result.get("show_feedback", true))
		and bool(result.get("show_feedback", false))
		and line_initiator_delta.is_empty() and line_target_delta.is_empty()
		and int((line_after.get("target", {}) as Dictionary).get("affection", 0)) == int((line_before.get("target", {}) as Dictionary).get("affection", 0))
		and fresh["npc"].mood == 50,
		"T24: a line-only response applies no roll, no deltas and no mood change"
	)


## --- T25: relationship band derived for responder toward speaker ------------

func _check_relationship_band() -> void:
	var templates: Array = _romantic_templates()
	var a: CharacterTemplate = templates[0]
	var b: CharacterTemplate = templates[1]
	var speaker := NpcInstance.from_template(a, "speaker")
	var listener := NpcInstance.from_template(b, "listener")
	speaker.get_meter(listener.instance_id)["familiarity"] = 60
	speaker.get_meter(listener.instance_id)["affection"] = 60
	var lover: String = DialogueResolver.relationship_type(speaker, listener, a, b)
	speaker.get_meter(listener.instance_id)["affection"] = -30
	var enemy: String = DialogueResolver.relationship_type(speaker, listener, a, b)
	_check(
		lover == DialogueResolver.TYPE_LOVER and enemy == DialogueResolver.TYPE_ENEMY,
		"T25: five-type band is derived from the responder's directed meter"
	)

	# Through the whole helper: the NPC's meter toward the player must select the
	# exact response, not the player's meter toward the NPC.
	var pair: Dictionary = _fresh_pair()
	var player: NpcInstance = pair["player"]
	var npc: NpcInstance = pair["npc"]
	npc.get_meter(player.instance_id)["familiarity"] = 25
	npc.get_meter(player.instance_id)["affection"] = 25
	player.get_meter(npc.instance_id)["affection"] = -50
	var topic: DialogueTopic = _topic("topic:band", "charisma", 0)
	var band_response: DialogueResponse = _response("r:friend", "Friend line", "topic:band", ["success"], ["Friend"])
	var conversation := Conversation.new()
	conversation.begin_player_initiated(player, npc, pair["pt"], pair["nt"], 5)
	conversation.choose_greeting([_greeting("g:any", "Hi")])
	conversation.choose_topic(topic)
	var selected: Dictionary = conversation.select_response([band_response], [topic])
	_check(
		selected.get("fallback", "") == "exact" and selected.get("selected_response_id", "") == "r:friend",
		"T26: select_response keys on the NPC's band toward the player"
	)


## --- T27-T29: NPC-initiated shape ------------------------------------------

func _check_npc_initiated() -> void:
	var pair: Dictionary = _fresh_pair()
	var npc: NpcInstance = pair["npc"]
	var player: NpcInstance = pair["player"]
	var topic: DialogueTopic = _topic("topic:opening", "charisma", 0)
	var familiarity_before: int = int(npc.get_meter(player.instance_id).get("familiarity", 0))
	var conversation := Conversation.new()
	conversation.begin_npc_initiated(npc, player, pair["nt"], pair["pt"], 31, "FREETIME1")
	var opening: Dictionary = conversation.choose_opening_topic([topic])
	_check(
		opening.get("id", "") == "topic:opening"
		and int(npc.get_meter(player.instance_id).get("familiarity", 0)) == familiarity_before
		and npc.mood == 50,
		"T27: the NPC opening topic is spoken only, with no roll or deltas"
	)

	var replies: Array = [
		_roll_response("reply:a", "A", "topic:opening", "charisma", 0),
		_roll_response("reply:b", "B", "topic:opening", "charisma", 0),
		_roll_response("reply:c", "C", "topic:opening", "charisma", 0),
	]
	var pool: Array = conversation.build_reply_pool(replies)
	_check(
		pool.size() >= 2 and pool.size() <= 3,
		"T28: NPC-initiated replies are a fixed 2-3 keyed pool"
	)

	var chosen: DialogueResponse = pool[0] as DialogueResponse
	var reply_result: Dictionary = conversation.choose_reply(chosen, [topic])
	var reply_before: Dictionary = reply_result.get("before", {})
	var reply_after: Dictionary = reply_result.get("after", {})
	_check(
		not reply_result.is_empty()
		and int(reply_result.get("stat_bonus", -1)) == player.get_stat(chosen.checked_stat)
		and int((reply_after.get("initiator", {}) as Dictionary).get("affection", 0)) > int((reply_before.get("initiator", {}) as Dictionary).get("affection", 0))
		and conversation.get_phase() == Conversation.Phase.DONE
		and not conversation.is_open() and conversation.get_turn() == 1,
		"T29: the reply rolls with the player as initiator, applies deltas and ends after one pick"
	)

	var empty_pair: Dictionary = _fresh_pair()
	var empty_conversation := Conversation.new()
	empty_conversation.begin_npc_initiated(
		empty_pair["npc"], empty_pair["player"], empty_pair["nt"], empty_pair["pt"], 99, "FREETIME1"
	)
	empty_conversation.choose_opening_topic([topic])
	var fallback_pool: Array = empty_conversation.build_reply_pool([])
	var fallback_reply: DialogueResponse = fallback_pool[0] as DialogueResponse
	var fallback_result: Dictionary = empty_conversation.choose_reply(fallback_reply, [topic])
	_check(
		fallback_pool.size() == 1 and fallback_reply != null and fallback_reply.is_line_only()
		and bool(fallback_result.get("line_only", false))
		and empty_conversation.is_done() and empty_pair["npc"].mood == 50,
		"T32: no authored replies yields a generated line-only option that ends the talk"
	)


## --- T33: layered fallback asserted through the Conversation seam ------------

func _check_conversation_fallbacks() -> void:
	var pair: Dictionary = _fresh_pair()
	var topic: DialogueTopic = _topic("topic:fallback", "charisma", 0)
	var default_response: DialogueResponse = _response("r:fallback_default", "Default line", "topic:fallback", [], [])
	var conversation := Conversation.new()
	conversation.begin_player_initiated(
		pair["player"], pair["npc"], pair["pt"], pair["nt"], 12, "PERIOD1"
	)
	conversation.choose_greeting([_greeting("g:any", "Hi")])
	conversation.choose_topic(topic)
	var default_result: Dictionary = conversation.select_response([default_response], [topic])
	_check(
		default_result.get("fallback", "") == "topic_default"
		and bool(default_result.get("line_only", false))
		and str(default_result.get("response_text", "")) == "Default line",
		"T33: a topic-only authored line flows through Conversation as a line-only outcome"
	)

	var generated_pair: Dictionary = _fresh_pair()
	var generated_conversation := Conversation.new()
	generated_conversation.begin_player_initiated(
		generated_pair["player"], generated_pair["npc"], generated_pair["pt"], generated_pair["nt"], 13, "PERIOD1"
	)
	generated_conversation.choose_greeting([_greeting("g:any", "Hi")])
	generated_conversation.choose_topic(topic)
	var generated_result: Dictionary = generated_conversation.select_response([], [topic])
	var generated_deltas: Dictionary = generated_result.get("deltas", {})
	_check(
		generated_result.get("fallback", "") == "generated"
		and not str(generated_result.get("response_text", "")).is_empty()
		and (generated_deltas.get("initiator", {}) as Dictionary).is_empty()
		and (generated_deltas.get("target", {}) as Dictionary).is_empty()
		and generated_conversation.get_phase() == Conversation.Phase.FOLLOWUP,
		"T34: no authored response produces a generated line and opens the follow-up pick"
	)


## --- T30-T31: full-flow determinism and both-party accumulation -------------

func _check_full_flow() -> void:
	var first: Dictionary = _full_flow(2026)
	var second: Dictionary = _full_flow(2026)
	_check(
		JSON.stringify(first.get("snapshot", {})) == JSON.stringify(second.get("snapshot", {}))
		and int(first.get("die_a", -1)) == int(second.get("die_a", -1))
		and int(first.get("die_b", -1)) == int(second.get("die_b", -1)),
		"T30: two full conversations with the same seed produce identical outcomes"
	)

	var player: NpcInstance = first.get("player")
	var npc: NpcInstance = first.get("npc")
	var player_familiarity: int = int(player.get_meter(npc.instance_id).get("familiarity", 0))
	var npc_familiarity: int = int(npc.get_meter(player.instance_id).get("familiarity", 0))
	_check(
		player_familiarity > 0 and npc_familiarity > 0,
		"T31: two picks update both parties' directed meters"
	)


func _full_flow(seed_value: int) -> Dictionary:
	var pair: Dictionary = _fresh_pair()
	var conversation := Conversation.new()
	conversation.begin_player_initiated(
		pair["player"], pair["npc"], pair["pt"], pair["nt"], seed_value, "PERIOD1"
	)
	var topic_a: DialogueTopic = _topic("topic:a", "charisma", 0)
	var topic_b: DialogueTopic = _topic("topic:b", "charisma", 0)
	conversation.choose_greeting([_greeting("g:any", "Hi")])
	var roll_a: Dictionary = conversation.choose_topic(topic_a)
	conversation.select_response([_response("r:a", "A", "topic:a", [], [])], [topic_a])
	var roll_b: Dictionary = conversation.choose_topic(topic_b)
	conversation.select_response([_response("r:b", "B", "topic:b", [], [])], [topic_b])
	return {
		"snapshot": conversation.snapshot(),
		"die_a": int(roll_a.get("die", -1)),
		"die_b": int(roll_b.get("die", -1)),
		"player": pair["player"],
		"npc": pair["npc"],
	}


## --- Fixtures ---------------------------------------------------------------

func _fresh_pair() -> Dictionary:
	var player_template: CharacterTemplate = ModLoader.get_resource(ModLoader.TYPE_CHARACTER, "char:alex") as CharacterTemplate
	var npc_template: CharacterTemplate = ModLoader.get_resource(ModLoader.TYPE_CHARACTER, "char:jordan") as CharacterTemplate
	var player := NpcInstance.from_template(player_template, "player")
	var npc := NpcInstance.from_template(npc_template, "npc:jordan")
	player.mood = 50
	npc.mood = 50
	return {
		"player": player, "npc": npc,
		"pt": player_template, "nt": npc_template,
	}


func _romantic_templates() -> Array:
	var a := CharacterTemplate.new()
	a.id = "template:a"
	a.gender = "female"
	a.orientation = "bi"
	var b := CharacterTemplate.new()
	b.id = "template:b"
	b.gender = "male"
	b.orientation = "bi"
	return [a, b]


func _greeting(id: String, text: String) -> DialogueGreeting:
	var greeting := DialogueGreeting.new()
	greeting.id = id
	greeting.text = text
	return greeting


func _topic(id: String, checked_stat: String, difficulty: int) -> DialogueTopic:
	var topic := DialogueTopic.new()
	topic.id = id
	topic.text = "Topic " + id
	topic.checked_stat = checked_stat
	topic.difficulty = difficulty
	topic.affection_delta_success = 3
	topic.familiarity_delta_success = 2
	topic.mood_delta_success = 1
	topic.affection_delta_failure = -1
	topic.familiarity_delta_failure = 1
	topic.mood_delta_failure = -1
	return topic


func _topic_with_modifier(id: String, checked_stat: String, difficulty: int) -> DialogueTopic:
	var topic: DialogueTopic = _topic(id, checked_stat, difficulty)
	topic.recipient_modifiers = [{
		"id": "charisma", "kind": "stat", "min": 0,
		"difficulty": 5, "delta_scale": 1.0,
	}]
	return topic


func _response(id: String, text: String, topic_id: String, outcomes: Array, bands: Array) -> DialogueResponse:
	var response := DialogueResponse.new()
	response.id = id
	response.text = text
	response.topic_id = topic_id
	response.outcomes = PackedStringArray(outcomes)
	response.relationship_bands = PackedStringArray(bands)
	return response


func _roll_response(id: String, text: String, topic_id: String, checked_stat: String, difficulty: int) -> DialogueResponse:
	var response: DialogueResponse = _response(id, text, topic_id, [], [])
	response.checked_stat = checked_stat
	response.difficulty = difficulty
	response.affection_delta_success = 3
	response.familiarity_delta_success = 2
	response.mood_delta_success = 1
	response.affection_delta_failure = -1
	response.familiarity_delta_failure = 1
	response.mood_delta_failure = -1
	return response


func _started_player_conversation(seed_value: int) -> Dictionary:
	var pair: Dictionary = _fresh_pair()
	var conversation := Conversation.new()
	conversation.begin_player_initiated(
		pair["player"], pair["npc"], pair["pt"], pair["nt"], seed_value, "PERIOD1"
	)
	return {"conversation": conversation, "pair": pair}


## --- Assertion / completion -------------------------------------------------

func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("[023] PASS " + label)
	else:
		_failed += 1
		print("[023] FAIL " + label)


func _finish() -> void:
	print("[023] RESULT passed=%d failed=%d" % [_passed, _failed])
	if _failed == 0:
		print("ALL_023_CHECKS_PASSED")
	else:
		print("SOME_023_CHECKS_FAILED")
	get_tree().quit(0 if _failed == 0 else 1)
