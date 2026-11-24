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

	# Recipient modifiers adjust the difficulty of the roll and the size of the
	# deltas *this target receives*. Trait keys are shared with the 014 filter so
	# ids/tags behave identically in both tickets.
	var effective_difficulty: int = topic.difficulty
	var recipient_scale: float = 1.0
	var target_keys: Array[String] = DialogueFilter.trait_keys(target_template)
	for entry in topic.recipient_modifiers:
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
	if not topic.checked_stat.is_empty():
		stat_bonus = initiator.get_stat(topic.checked_stat)
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

	var base_affection: int = topic.affection_delta_success if success else topic.affection_delta_failure
	var base_familiarity: int = topic.familiarity_delta_success if success else topic.familiarity_delta_failure
	var base_mood: int = topic.mood_delta_success if success else topic.mood_delta_failure

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
		"topic_id": topic.id,
		"topic_text": topic.text,
		"success": success,
		"checked_stat": topic.checked_stat,
		"stat_bonus": stat_bonus,
		"familiarity_bonus": familiarity_bonus,
		"die": die,
		"roll": roll,
		"difficulty": topic.difficulty,
		"effective_difficulty": effective_difficulty,
		"margin": margin,
		"margin_scale": margin_scale,
		"recipient_scale": recipient_scale,
		"deltas": {"initiator": initiator_delta, "target": target_delta},
		"before": before,
		"after": after,
		"relationship_changed": (
			str((before["initiator"] as Dictionary).get("relationship", "")) != str((after["initiator"] as Dictionary).get("relationship", ""))
			or str((before["target"] as Dictionary).get("relationship", "")) != str((after["target"] as Dictionary).get("relationship", ""))
		),
	}


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
