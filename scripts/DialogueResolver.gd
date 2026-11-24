class_name DialogueResolver
extends RefCounted

## DialogueResolver
##
## Pure, headless-testable resolution of one selected dialogue topic (ticket
## 015). Given an initiator and a target — both `NpcInstance` resources — plus
## their authored templates, it rolls the threshold check, scales the deltas,
## writes both parties' directed meters and moods, then derives each party's
## relationship type from the updated meters.
##
## No scene tree, autoload globals or hidden state: a non-negative `seed_value`
## makes the roll reproducible for verification. `Game.gd` is the only caller in
## play; ticket 016 can reuse the same seam for NPC-initiated interactions.


## --- Relationship type names ------------------------------------------------

const TYPE_STRANGER: String = "Stranger"
const TYPE_ACQUAINTANCE: String = "Acquaintance"
const TYPE_FRIEND: String = "Friend"
const TYPE_ENEMY: String = "Enemy"
const TYPE_LOVER: String = "Lover"


## --- Roll / scaling bounds --------------------------------------------------

## Inclusive upper bound of the random term in random(0..5).
const DIE_MAX: int = 5
## |margin| at which margin scaling reaches its maximum.
const MARGIN_SCALE_DIVISOR: float = 5.0
const MARGIN_SCALE_MAX: float = 2.0
## Combined recipient modifier scale is clamped to this range.
const RECIPIENT_SCALE_MIN: float = 0.25
const RECIPIENT_SCALE_MAX: float = 2.0


## --- Meter / mood clamps ----------------------------------------------------

const FAMILIARITY_MIN: int = 0
const FAMILIARITY_MAX: int = 100
const AFFECTION_MIN: int = -100
const AFFECTION_MAX: int = 100
const MOOD_MIN: int = 0
const MOOD_MAX: int = 100


## --- Relationship thresholds ------------------------------------------------

const REL_LOVER_FAM: int = 60
const REL_LOVER_AFF: int = 60
const REL_ENEMY_AFF: int = -20
const REL_FRIEND_FAM: int = 20
const REL_FRIEND_AFF: int = 20


## Resolve `topic` for the pair and return a Dictionary describing the outcome.
##
## The result carries the roll breakdown, the per-party deltas, and before/after
## snapshots of each party's meter + mood + relationship type so feedback and
## later tickets consume one payload. Returns {} for a null topic/instance.
static func resolve(
	topic: DialogueTopic,
	initiator: NpcInstance,
	target: NpcInstance,
	initiator_template: CharacterTemplate,
	target_template: CharacterTemplate,
	seed_value: int = -1
) -> Dictionary:
	if topic == null or initiator == null or target == null:
		return {}
	return _resolve_fields(
		_roll_fields(
			topic.id, topic.text, topic.checked_stat, topic.difficulty,
			topic.affection_delta_success, topic.familiarity_delta_success, topic.mood_delta_success,
			topic.affection_delta_failure, topic.familiarity_delta_failure, topic.mood_delta_failure
		),
		topic.recipient_modifiers,
		initiator, target, initiator_template, target_template, seed_value
	)


## Resolve a `DialogueResponse` using its OWN roll fields (ticket 023). A response
## is line-only when `checked_stat` is empty; in that case no roll runs and no
## meter/mood is touched — the returned payload still has the standard shape so
## UI and verification can consume either kind uniformly.
##
## `topics` is the array of authored `DialogueTopic` resources (ticket 024 passes
## ModLoader.get_all(TYPE_DIALOGUE)). `DialogueResponse` deliberately carries no
## recipient modifiers (021 decision), so when the response's `topic_id` resolves
## to one of those topics its recipient modifiers are reused; generic lines get
## none. The helper stays pure: no autoload or scene-tree access.
static func resolve_response(
	response: DialogueResponse,
	initiator: NpcInstance,
	target: NpcInstance,
	initiator_template: CharacterTemplate,
	target_template: CharacterTemplate,
	topics: Array = [],
	seed_value: int = -1
) -> Dictionary:
	if response == null or initiator == null or target == null:
		return {}

	if response.is_line_only():
		return _line_only_result(response, initiator, target, initiator_template, target_template)

	var keyed_topic: DialogueTopic = _find_topic(topics, response.topic_id)
	var modifiers: Array = keyed_topic.recipient_modifiers if keyed_topic != null else []
	var result: Dictionary = _resolve_fields(
		_roll_fields(
			response.id, response.text, response.checked_stat, response.difficulty,
			response.affection_delta_success, response.familiarity_delta_success, response.mood_delta_success,
			response.affection_delta_failure, response.familiarity_delta_failure, response.mood_delta_failure
		),
		modifiers,
		initiator, target, initiator_template, target_template, seed_value
	)
	result["response_id"] = response.id
	result["response_text"] = response.text
	result["line_only"] = false
	return result


## --- Shared roll core --------------------------------------------------------

## Normalise a DialogueTopic or DialogueResponse into one roll-field payload so
## both resources flow through exactly the same roll/scaling/mutation code.
static func _roll_fields(
	id: String, text: String, checked_stat: String, difficulty: int,
	affection_success: int, familiarity_success: int, mood_success: int,
	affection_failure: int, familiarity_failure: int, mood_failure: int
) -> Dictionary:
	return {
		"id": id,
		"text": text,
		"checked_stat": checked_stat,
		"difficulty": difficulty,
		"affection_success": affection_success,
		"familiarity_success": familiarity_success,
		"mood_success": mood_success,
		"affection_failure": affection_failure,
		"familiarity_failure": familiarity_failure,
		"mood_failure": mood_failure,
	}


## The single implementation of the threshold check, margin scaling, recipient
## modifiers, dual-party writes, and relationship re-derivation. Both resolve()
## and resolve_response() delegate here so the two paths cannot drift.
static func _resolve_fields(
	fields: Dictionary,
	recipient_modifiers: Array,
	initiator: NpcInstance,
	target: NpcInstance,
	initiator_template: CharacterTemplate,
	target_template: CharacterTemplate,
	seed_value: int
) -> Dictionary:
	# Recipient modifiers adjust the difficulty of the roll and the size of the
	# deltas *this target receives*. Trait keys are shared with the 014 filter so
	# ids/tags behave identically in both tickets.
	var effective_difficulty: int = int(fields.get("difficulty", 0))
	var recipient_scale: float = 1.0
	var target_keys: Array[String] = DialogueFilter.trait_keys(target_template)
	for entry in recipient_modifiers:
		if not (entry is Dictionary):
			continue
		var modifier: Dictionary = entry
		var id: String = str(modifier.get("id", ""))
		if id.is_empty():
			continue
		var kind: String = str(modifier.get("kind", "trait")).strip_edges().to_lower()
		var matched: bool = false
		if kind == "stat":
			# get_stat() returns 0 for unknown names, so a typo with the default
			# min of 0 would match every recipient. Require the stat to actually
			# exist on the instance (mods may add stats; typos may not).
			matched = target.stats.has(id) and target.get_stat(id) >= int(modifier.get("min", 0))
		else:
			matched = target_keys.has(id)
		if matched:
			effective_difficulty += int(modifier.get("difficulty", 0))
			recipient_scale *= float(modifier.get("delta_scale", 1.0))
	recipient_scale = clampf(recipient_scale, RECIPIENT_SCALE_MIN, RECIPIENT_SCALE_MAX)

	# The threshold check: stat + (familiarity / 10) + random(0..5).
	var stat_bonus: int = 0
	var checked_stat: String = str(fields.get("checked_stat", ""))
	if not checked_stat.is_empty():
		stat_bonus = initiator.get_stat(checked_stat)
	var initiator_meter: Dictionary = initiator.get_meter(target.instance_id)
	var familiarity_bonus: int = int(initiator_meter.get("familiarity", 0)) / 10

	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.seed = Time.get_ticks_usec() ^ initiator.instance_id.hash()
	var die: int = rng.randi_range(0, DIE_MAX)
	var roll: int = stat_bonus + familiarity_bonus + die
	var margin: int = roll - effective_difficulty
	var success: bool = margin >= 0

	# Margin scales affection only, bounded so a huge margin cannot dominate the
	# authored delta. Larger misses hurt more; larger wins reward more.
	var margin_scale: float = clampf(
		1.0 + absf(float(margin)) / MARGIN_SCALE_DIVISOR, 1.0, MARGIN_SCALE_MAX
	)

	var base_affection: int = int(fields.get("affection_success", 0)) if success else int(fields.get("affection_failure", 0))
	var base_familiarity: int = int(fields.get("familiarity_success", 0)) if success else int(fields.get("familiarity_failure", 0))
	var base_mood: int = int(fields.get("mood_success", 0)) if success else int(fields.get("mood_failure", 0))

	var initiator_delta: Dictionary = {
		"affection": roundi(float(base_affection) * margin_scale),
		"familiarity": base_familiarity,
		"mood": base_mood,
	}
	var target_delta: Dictionary = {
		"affection": roundi(float(base_affection) * margin_scale * recipient_scale),
		"familiarity": roundi(float(base_familiarity) * recipient_scale),
		"mood": roundi(float(base_mood) * recipient_scale),
	}

	var before: Dictionary = _snapshot_pair(initiator, target, initiator_template, target_template)
	_apply(initiator, target.instance_id, initiator_delta)
	_apply(target, initiator.instance_id, target_delta)
	var after: Dictionary = _snapshot_pair(initiator, target, initiator_template, target_template)

	return {
		"topic_id": str(fields.get("id", "")),
		"topic_text": str(fields.get("text", "")),
		"success": success,
		"checked_stat": checked_stat,
		"stat_bonus": stat_bonus,
		"familiarity_bonus": familiarity_bonus,
		"die": die,
		"roll": roll,
		"difficulty": int(fields.get("difficulty", 0)),
		"effective_difficulty": effective_difficulty,
		"margin": margin,
		"margin_scale": margin_scale,
		"recipient_scale": recipient_scale,
		"deltas": {"initiator": initiator_delta, "target": target_delta},
		"before": before,
		"after": after,
		"show_feedback": true,
		"relationship_changed": (
			str((before["initiator"] as Dictionary).get("relationship", "")) != str((after["initiator"] as Dictionary).get("relationship", ""))
			or str((before["target"] as Dictionary).get("relationship", "")) != str((after["target"] as Dictionary).get("relationship", ""))
		),
	}


## A line-only reaction has no roll and no deltas: before == after, and all roll
## fields are zeroed so nothing downstream can mistake it for a successful check.
static func _line_only_result(
	response: DialogueResponse,
	initiator: NpcInstance,
	target: NpcInstance,
	initiator_template: CharacterTemplate,
	target_template: CharacterTemplate
) -> Dictionary:
	var before: Dictionary = _snapshot_pair(initiator, target, initiator_template, target_template)
	return {
		"response_id": response.id,
		"response_text": response.text,
		"topic_id": response.topic_id,
		"topic_text": response.text,
		"line_only": true,
		"show_feedback": false,
		"success": false,
		"checked_stat": "",
		"stat_bonus": 0,
		"familiarity_bonus": 0,
		"die": 0,
		"roll": 0,
		"difficulty": 0,
		"effective_difficulty": 0,
		"margin": 0,
		"margin_scale": 1.0,
		"recipient_scale": 1.0,
		"deltas": {"initiator": {}, "target": {}},
		"before": before,
		"after": _snapshot_pair(initiator, target, initiator_template, target_template),
		"relationship_changed": false,
	}


## Find an authored topic by id in the array supplied by the caller. Kept
## autoload-free on purpose; the pure helper never reaches into the registry.
static func _find_topic(topics: Array, topic_id: String) -> DialogueTopic:
	if topic_id.is_empty():
		return null
	for item in topics:
		var topic: DialogueTopic = item as DialogueTopic
		if topic != null and topic.id == topic_id:
			return topic
	return null


## Derive the relationship type one instance holds toward `other` from its
## directed meter. Lover requires the mutual orientation/gender gate; a pair
## that fails it falls through to Friend. Always returns one of the five names.
static func relationship_type(
	instance: NpcInstance,
	other: NpcInstance,
	template: CharacterTemplate,
	other_template: CharacterTemplate
) -> String:
	if instance == null or other == null:
		return TYPE_STRANGER
	var raw: Variant = instance.meters.get(other.instance_id, null)
	var meter: Dictionary = raw if raw is Dictionary else {}
	var familiarity: int = int(meter.get("familiarity", 0))
	var affection: int = int(meter.get("affection", 0))

	if familiarity >= REL_LOVER_FAM and affection >= REL_LOVER_AFF and _mutual_romance(template, other_template):
		return TYPE_LOVER
	if affection <= REL_ENEMY_AFF:
		return TYPE_ENEMY
	if familiarity >= REL_FRIEND_FAM and affection >= REL_FRIEND_AFF:
		return TYPE_FRIEND
	if familiarity >= REL_FRIEND_FAM:
		return TYPE_ACQUAINTANCE
	return TYPE_STRANGER


## --- Private helpers --------------------------------------------------------

## Apply one party's deltas to its directed meter toward the other party and to
## its global mood. get_meter() creates a missing meter; resolution owns writes.
static func _apply(instance: NpcInstance, other_id: String, delta: Dictionary) -> void:
	var meter: Dictionary = instance.get_meter(other_id)
	meter["affection"] = clampi(
		int(meter.get("affection", 0)) + int(delta.get("affection", 0)), AFFECTION_MIN, AFFECTION_MAX
	)
	meter["familiarity"] = clampi(
		int(meter.get("familiarity", 0)) + int(delta.get("familiarity", 0)), FAMILIARITY_MIN, FAMILIARITY_MAX
	)
	instance.mood = clampi(instance.mood + int(delta.get("mood", 0)), MOOD_MIN, MOOD_MAX)


static func _snapshot_pair(
	initiator: NpcInstance,
	target: NpcInstance,
	initiator_template: CharacterTemplate,
	target_template: CharacterTemplate
) -> Dictionary:
	return {
		"initiator": _party_snapshot(initiator, target, initiator_template, target_template),
		"target": _party_snapshot(target, initiator, target_template, initiator_template),
	}


static func _party_snapshot(
	instance: NpcInstance,
	other: NpcInstance,
	template: CharacterTemplate,
	other_template: CharacterTemplate
) -> Dictionary:
	var raw: Variant = instance.meters.get(other.instance_id, null)
	var meter: Dictionary = raw if raw is Dictionary else {}
	return {
		"familiarity": int(meter.get("familiarity", 0)),
		"affection": int(meter.get("affection", 0)),
		"mood": instance.mood,
		"relationship": relationship_type(instance, other, template, other_template),
	}


static func _mutual_romance(a: CharacterTemplate, b: CharacterTemplate) -> bool:
	if a == null or b == null:
		return false
	return (
		_orientation_accepts(a.orientation, a.gender, b.gender)
		and _orientation_accepts(b.orientation, b.gender, a.gender)
	)


## True when `orientation` permits attraction to `other_gender`. Unknown or
## empty orientations fail closed so modded data cannot unlock romance by typo.
static func _orientation_accepts(orientation: String, self_gender: String, other_gender: String) -> bool:
	if other_gender.is_empty():
		return false
	match orientation.strip_edges().to_lower():
		"none":
			return false
		"hetero", "heterosexual", "straight":
			return other_gender != self_gender
		"homo", "homosexual", "gay", "lesbian":
			return other_gender == self_gender
		"bi", "bisexual", "pan", "pansexual":
			return true
		_:
			return false
