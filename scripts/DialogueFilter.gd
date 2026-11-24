class_name DialogueFilter
extends RefCounted

## DialogueFilter
##
## Pure, headless-testable dialogue eligibility and pool selection for the
## pair-agnostic interaction pipeline (ticket 014). Given an initiator and a
## target — both `NpcInstance` resources — plus their authored templates, it
## decides which `DialogueTopic` resources are eligible and builds a randomized
## pool of 3–5 of them.
##
## This helper never touches the scene tree, autoload globals or an instance's
## meters: it only reads them. Ticket 015 owns resolution and all mutations.


## Bounds for the offered topic pool (the spec asks for 3–5).
const MIN_POOL_SIZE: int = 3
const MAX_POOL_SIZE: int = 5


## True when every condition on `topic` passes for this pair. A null topic or
## missing instance fails closed; a missing template contributes no trait keys,
## so any topic that requires a trait/interest cannot be eligible by accident.
static func is_eligible(
	topic: DialogueTopic,
	initiator: NpcInstance,
	target: NpcInstance,
	initiator_template: CharacterTemplate,
	target_template: CharacterTemplate
) -> bool:
	if topic == null or initiator == null or target == null:
		return false

	if topic.min_mood > 0 and initiator.mood < topic.min_mood:
		return false

	# Read-only: filtering must not create a meter that 015 would then treat as
	# an existing relationship.
	var meter: Dictionary = _meter(initiator, target.instance_id)
	if topic.min_familiarity > 0 and int(meter.get("familiarity", 0)) < topic.min_familiarity:
		return false
	# Affection ranges -100..100 and 0 means "no gate", so negative thresholds
	# (e.g. "must not be an enemy") are meaningful and must still be enforced.
	if topic.min_affection != 0 and int(meter.get("affection", 0)) < topic.min_affection:
		return false

	var keys: Array[String] = _trait_keys(initiator_template)
	keys.append_array(_trait_keys(target_template))
	if not _contains_all(topic.required_interests, keys):
		return false
	if not _contains_all(topic.required_traits, keys):
		return false

	if not topic.required_stat.is_empty():
		if initiator.get_stat(topic.required_stat) < topic.required_stat_min:
			return false

	return true


## Eligible topics from `topics`, shuffled and sliced to a random size in
## [MIN_POOL_SIZE, MAX_POOL_SIZE] (capped by how many are eligible). Returns an
## empty array when nothing is eligible. `seed_value >= 0` makes the result
## deterministic for headless tests; play passes a tick-derived seed instead.
static func build_pool(
	topics: Array,
	initiator: NpcInstance,
	target: NpcInstance,
	initiator_template: CharacterTemplate,
	target_template: CharacterTemplate,
	seed_value: int = -1
) -> Array:
	var eligible: Array = []
	for item in topics:
		var topic: DialogueTopic = item as DialogueTopic
		if topic != null and is_eligible(topic, initiator, target, initiator_template, target_template):
			eligible.append(topic)
	if eligible.is_empty():
		return []

	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		# Vary across repeated conversations while staying independent of the
		# global RNG used by the day clock and NPC AI. Null-safe for ticket 016,
		# which may not have an initiator instance at this point.
		var initiator_id: String = initiator.instance_id if initiator != null else ""
		rng.seed = Time.get_ticks_usec() ^ initiator_id.hash()

	_shuffle(rng, eligible)
	var size: int = clampi(rng.randi_range(MIN_POOL_SIZE, MAX_POOL_SIZE), 1, eligible.size())
	return eligible.slice(0, size)


## The initiator's directed meter toward `target_id`, or an empty dictionary.
## Deliberately does not call NpcInstance.get_meter(), which creates a meter.
static func _meter(initiator: NpcInstance, target_id: String) -> Dictionary:
	if target_id.is_empty():
		return {}
	var raw: Variant = initiator.meters.get(target_id, null)
	return raw if raw is Dictionary else {}


## Every trait id and tag from both the `Trait` resources and plain-string
## entries of a template's `traits` array. Missing templates yield no keys.
static func _trait_keys(template: CharacterTemplate) -> Array[String]:
	var keys: Array[String] = []
	if template == null:
		return keys
	for item in template.traits:
		if item is Trait:
			var trait_resource: Trait = item as Trait
			if not trait_resource.id.is_empty():
				keys.append(trait_resource.id)
			for tag in trait_resource.tags:
				if not str(tag).is_empty():
					keys.append(str(tag))
		elif item is String:
			if not (item as String).is_empty():
				keys.append(item as String)
	return keys


## All required ids must be present; empty ids are ignored as "no requirement".
static func _contains_all(required: PackedStringArray, available: Array[String]) -> bool:
	for id in required:
		if id.is_empty():
			continue
		if not available.has(id):
			return false
	return true


## Seeded Fisher–Yates: Array.shuffle() uses the global RNG and is not testable.
static func _shuffle(rng: RandomNumberGenerator, values: Array) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = values[i]
		values[i] = values[j]
		values[j] = tmp
