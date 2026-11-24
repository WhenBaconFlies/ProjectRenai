class_name Conversation
extends RefCounted

## Conversation
##
## Pure, headless-testable session state for one conversation (ticket 023). It owns
## the phase flow, the player-pick limit, the initiator/target ids and a seeded
## RNG. It never touches the scene tree, an autoload, or the clock: callers pass
## in the authored resource arrays and the current TimeManager period string.
##
## Player-initiated shape (max two player picks):
##   GREETING -> TOPIC -> RESPONSE -> FOLLOWUP -> RESPONSE -> DONE
## NPC-initiated shape (one player reply):
##   GREETING (spoken topic, no roll/deltas) -> TOPIC (2-3 replies) -> DONE
##
## Filtering stays in DialogueFilter, rolls and meter writes stay in
## DialogueResolver. This class only sequences them and keeps random draws
## reproducible from one caller-supplied seed.


## --- Session phases ---------------------------------------------------------

enum Phase {
	GREETING,
	TOPIC,
	RESPONSE,
	FOLLOWUP,
	DONE,
}

## Maximum player topic picks in a player-initiated conversation. The greeting
## is not counted; each pick gets its own roll.
const MAX_TURNS: int = 2

## Fixed reply-option count for an NPC-initiated conversation (spec: 2-3).
const MIN_REPLIES: int = 2
const MAX_REPLIES: int = 3

## Last-resort spoken reply when an opening topic has no authored reply options.
## Line-only, so choosing it ends the talk with no meter/mood change.
const GENERATED_REPLY_TEXT: String = "I'm not sure what to say about that."

const MODE_PLAYER_INITIATED: String = "player"
const MODE_NPC_INITIATED: String = "npc"


## --- Owned state ------------------------------------------------------------

var _mode: String = MODE_PLAYER_INITIATED
var _phase: Phase = Phase.GREETING
var _turn: int = 0
var _open: bool = false
var _period: String = ""

var _initiator: NpcInstance = null
var _target: NpcInstance = null
var _initiator_template: CharacterTemplate = null
var _target_template: CharacterTemplate = null

var _rng: RandomNumberGenerator = null
## Cached per-step seeds keep repeated queries within one turn deterministic.
var _seed_cache: Dictionary = {}

var _opening: Dictionary = {}
var _last_roll: Dictionary = {}
var _last_response: Dictionary = {}
var _last_topic: DialogueTopic = null


## --- Begin ------------------------------------------------------------------

## Start a player-initiated conversation. `player` speaks the topic picks and
## holds the roll initiator role; `npc` speaks the greeting and reactive lines.
func begin_player_initiated(
	player: NpcInstance,
	npc: NpcInstance,
	player_template: CharacterTemplate,
	npc_template: CharacterTemplate,
	seed_value: int,
	period: String = ""
) -> void:
	_begin(MODE_PLAYER_INITIATED, player, npc, player_template, npc_template, seed_value, period)


## Start an NPC-initiated conversation. The NPC speaks an opening topic with no
## roll or deltas; the player then picks one reply and the conversation ends.
func begin_npc_initiated(
	npc: NpcInstance,
	player: NpcInstance,
	npc_template: CharacterTemplate,
	player_template: CharacterTemplate,
	seed_value: int,
	period: String = ""
) -> void:
	_begin(MODE_NPC_INITIATED, npc, player, npc_template, player_template, seed_value, period)


func _begin(
	mode: String,
	initiator: NpcInstance,
	target: NpcInstance,
	initiator_template: CharacterTemplate,
	target_template: CharacterTemplate,
	seed_value: int,
	period: String
) -> void:
	_mode = mode
	_initiator = initiator
	_target = target
	_initiator_template = initiator_template
	_target_template = target_template
	_period = period
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	_seed_cache.clear()
	_phase = Phase.GREETING
	_turn = 0
	_open = true
	_opening = {}
	_last_roll = {}
	_last_response = {}
	_last_topic = null


## --- Player-initiated flow ---------------------------------------------------

## Choose the opening line for a player-initiated talk. The relationship band is
## derived for the NPC (the speaker) toward the player, per the v2 decision.
## Returns the selection Dictionary from DialogueFilter.select_greeting().
func choose_greeting(greetings: Array) -> Dictionary:
	if not _open or _phase != Phase.GREETING:
		return {}
	var speaker: NpcInstance = _line_speaker()
	var listener: NpcInstance = _listener()
	if speaker == null or listener == null:
		return {}
	var band: String = DialogueResolver.relationship_type(
		speaker, listener, _line_speaker_template(), _listener_template()
	)
	_opening = DialogueFilter.select_greeting(
		greetings, band, speaker.mood, _period, _combined_keys(), _seed_for("greeting")
	)
	_phase = Phase.TOPIC
	return _opening


## Build the eligible topic pool for the next player pick. Read-only with respect
## to relationship state; returns [] when the conversation cannot accept a pick.
func build_topic_pool(topics: Array) -> Array:
	if not can_pick_topic():
		return []
	return DialogueFilter.build_pool(
		topics, _roll_initiator(), _roll_target(),
		_roll_initiator_template(), _roll_target_template(), _seed_for("pool")
	)


## Resolve one player topic pick. Increments the turn counter and moves to
## RESPONSE. Returns DialogueResolver.resolve()'s outcome payload.
func choose_topic(topic: DialogueTopic) -> Dictionary:
	if not can_pick_topic() or topic == null:
		return {}
	_last_topic = topic
	_last_roll = DialogueResolver.resolve(
		topic, _roll_initiator(), _roll_target(),
		_roll_initiator_template(), _roll_target_template(), _seed_for("roll")
	)
	_turn += 1
	_phase = Phase.RESPONSE
	return _last_roll


## Select and resolve the reactive NPC line for the last roll. Uses the layered
## fallback in DialogueFilter.select_response(), then DialogueResolver's
## response-aware entry point (skipping resolution for line-only lines).
## `topics` supplies authored topics so response recipient modifiers can be
## reused; pass an empty array for generic lines.
func select_response(responses: Array, topics: Array = []) -> Dictionary:
	if not _open or _phase != Phase.RESPONSE:
		return {}
	var outcome: String = "success" if bool(_last_roll.get("success", false)) else "failure"
	var speaker: NpcInstance = _line_speaker()
	var listener: NpcInstance = _listener()
	var band: String = DialogueResolver.relationship_type(
		speaker, listener, _line_speaker_template(), _listener_template()
	)
	var topic_id: String = _last_topic.id if _last_topic != null else ""
	var selection: Dictionary = DialogueFilter.select_response(
		responses, topic_id, outcome, band, _seed_for("response")
	)

	var chosen: DialogueResponse = selection.get("resource") as DialogueResponse
	if chosen == null:
		# Code-generated last resort: a temporary line-only response flows through
		# the same result shape as an authored line, with no roll or deltas.
		chosen = DialogueResponse.new()
		chosen.id = str(selection.get("id", "response:generated"))
		chosen.text = str(selection.get("text", ""))

	_last_response = DialogueResolver.resolve_response(
		chosen, _roll_initiator(), _roll_target(),
		_roll_initiator_template(), _roll_target_template(), topics, _seed_for("response_roll")
	)
	_last_response["fallback"] = str(selection.get("fallback", "generated"))
	_last_response["selected_response_id"] = str(selection.get("id", chosen.id))
	_advance_after_response()
	return _last_response


## --- NPC-initiated flow -----------------------------------------------------

## Pick one of the NPC's authored topics as its opening line. Deliberately spoken
## only: no roll, no deltas — the player's reply is the only state change.
func choose_opening_topic(topics: Array) -> Dictionary:
	if not _open or _phase != Phase.GREETING or _mode != MODE_NPC_INITIATED:
		return {}
	var pool: Array = DialogueFilter.build_pool(
		topics, _initiator, _target, _initiator_template, _target_template, _seed_for("opening")
	)
	var chosen: DialogueTopic = NpcInitiation.pick_topic(pool, _seed_for("opening_pick"))
	if chosen == null:
		_opening = {"id": "", "text": "", "fallback": "generated", "resource": null}
	else:
		_opening = {
			"id": chosen.id, "text": chosen.text, "fallback": "topic", "resource": chosen,
		}
	_phase = Phase.TOPIC
	return _opening


## Build the fixed-size (2-3) reply pool for the player. Replies are keyed by the
## opening topic id and filtered by the optional trait/mood/interest fields on
## DialogueResponse; their text is the player's spoken line. When no authored
## reply exists for the opening topic, a single generated line-only option keeps
## the player in control and lets choose_reply() end the talk with no deltas.
func build_reply_pool(responses: Array) -> Array:
	if not _open or _phase != Phase.TOPIC or _mode != MODE_NPC_INITIATED:
		return []
	var pool: Array = DialogueFilter.build_reply_pool(
		responses, str(_opening.get("id", "")),
		_target, _initiator, _target_template, _initiator_template,
		_seed_for("replies"), MIN_REPLIES, MAX_REPLIES
	)
	if pool.is_empty():
		var generated := DialogueResponse.new()
		generated.id = "response:generated_reply"
		generated.text = GENERATED_REPLY_TEXT
		pool.append(generated)
	return pool


## Resolve the player's chosen reply. The player is the roll initiator and the
## NPC the target, so the reply's deltas are the final (and only) state change.
## One reply ends the conversation.
func choose_reply(response: DialogueResponse, topics: Array = []) -> Dictionary:
	if (
		not _open or _phase != Phase.TOPIC or _mode != MODE_NPC_INITIATED
		or response == null
	):
		return {}
	_last_topic = null
	_last_roll = {}
	_last_response = DialogueResolver.resolve_response(
		response, _target, _initiator, _target_template, _initiator_template,
		topics, _seed_for("reply_roll")
	)
	_turn = 1
	_phase = Phase.DONE
	_open = false
	return _last_response


## --- Lifecycle / inspection -------------------------------------------------

## End the conversation early (the player chose to leave). Safe to call twice.
func leave() -> void:
	_phase = Phase.DONE
	_open = false


## True while the conversation is open.
func is_open() -> bool:
	return _open


## True once the conversation has ended (two picks, one reply, or an early leave).
func is_done() -> bool:
	return _phase == Phase.DONE


## Current phase.
func get_phase() -> Phase:
	return _phase


## Current phase as a string, convenient for headless assertions and UI logs.
func phase_name() -> String:
	return Phase.keys()[_phase]


## Number of player picks used (0, 1 or 2). The greeting is not counted.
func get_turn() -> int:
	return _turn


## True when a player topic pick is allowed in the current phase.
func can_pick_topic() -> bool:
	return _open and _turn < MAX_TURNS and (_phase == Phase.TOPIC or _phase == Phase.FOLLOWUP)


## True for the NPC-initiated shape.
func is_npc_initiated() -> bool:
	return _mode == MODE_NPC_INITIATED


## Stable id of the initiator instance.
func get_initiator_id() -> String:
	return _initiator.instance_id if _initiator != null else ""


## Stable id of the target instance.
func get_target_id() -> String:
	return _target.instance_id if _target != null else ""


## Opening selection (greeting or spoken NPC topic).
func get_opening() -> Dictionary:
	return _opening


## Outcome payload of the most recent topic/reply roll.
func get_last_roll() -> Dictionary:
	return _last_roll


## Outcome payload of the most recent spoken response (may be line-only).
func get_last_response() -> Dictionary:
	return _last_response


## Plain Dictionary summary for verification; no resource references leak out.
func snapshot() -> Dictionary:
	return {
		"mode": _mode,
		"phase": phase_name(),
		"turn": _turn,
		"open": _open,
		"initiator_id": get_initiator_id(),
		"target_id": get_target_id(),
		"opening_id": str(_opening.get("id", "")),
		"last_roll_success": bool(_last_roll.get("success", false)),
		"last_response_id": str(_last_response.get("selected_response_id", _last_response.get("response_id", ""))),
	}


## --- Role helpers -----------------------------------------------------------

## The instance whose spoken line expresses the relationship band: the NPC in
## both conversation shapes.
func _line_speaker() -> NpcInstance:
	return _target if _mode == MODE_PLAYER_INITIATED else _initiator


func _line_speaker_template() -> CharacterTemplate:
	return _target_template if _mode == MODE_PLAYER_INITIATED else _initiator_template


func _listener() -> NpcInstance:
	return _initiator if _mode == MODE_PLAYER_INITIATED else _target


func _listener_template() -> CharacterTemplate:
	return _initiator_template if _mode == MODE_PLAYER_INITIATED else _target_template


## The roll direction: the player is always the initiator of a check.
func _roll_initiator() -> NpcInstance:
	return _initiator if _mode == MODE_PLAYER_INITIATED else _target


func _roll_initiator_template() -> CharacterTemplate:
	return _initiator_template if _mode == MODE_PLAYER_INITIATED else _target_template


func _roll_target() -> NpcInstance:
	return _target if _mode == MODE_PLAYER_INITIATED else _initiator


func _roll_target_template() -> CharacterTemplate:
	return _target_template if _mode == MODE_PLAYER_INITIATED else _initiator_template


## Combined trait/interest keys of both parties, reused by greeting and reply gates.
func _combined_keys() -> Array[String]:
	var keys: Array[String] = DialogueFilter.trait_keys(_initiator_template)
	keys.append_array(DialogueFilter.trait_keys(_target_template))
	return keys


## Stable, per-step sub-seed drawn from the owned RNG. Cached so that repeating a
## query in the same turn cannot change the conversation's random sequence.
func _seed_for(step: String) -> int:
	var key: String = "%s:%d" % [step, _turn]
	if _seed_cache.has(key):
		return int(_seed_cache[key])
	var value: int = int(_rng.randi())
	_seed_cache[key] = value
	return value


func _advance_after_response() -> void:
	if _turn >= MAX_TURNS:
		_phase = Phase.DONE
		_open = false
	else:
		_phase = Phase.FOLLOWUP
