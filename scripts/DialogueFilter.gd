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


## Public read-only access to a template's trait ids/tags. Ticket 015's resolver
## uses the same key set when matching recipient trait modifiers.
static func trait_keys(template: CharacterTemplate) -> Array[String]:
	return _trait_keys(template)


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


## --- Greeting selection (ticket 023) ----------------------------------------

## Generated line used only when the author supplied no greetings at all. Authored
## content always wins; this is the last resort that keeps a talk from dead-ending.
const GENERATED_GREETING_TEXT: String = "Hey — good to see you."


## True when every authored gate on `greeting` passes. `band` is the derived
## relationship type of the speaker toward the listener, `period` is a
## TimeManager DayState name, and `keys` is the combined trait/interest key set
## of both parties. Reads only — filtering never creates a meter.
static func is_greeting_eligible(
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
	if not _contains_all(greeting.required_traits, keys):
		return false
	if not _contains_all(greeting.required_interests, keys):
		return false
	return true


## Pick a greeting with a seeded weighted draw. Eligibility covers all four
## factors; if none pass, the safe fallback draws from every authored greeting
## with text (ignoring gates). If there are no greetings at all, a generated line
## is returned. The result Dictionary always has `id`, `text` and `fallback`
## ("eligible" | "any_eligible" | "generated").
static func select_greeting(
	greetings: Array,
	band: String,
	mood: int,
	period: String,
	keys: Array[String],
	seed_value: int = -1
) -> Dictionary:
	var eligible: Array = []
	var any_text: Array = []
	for item in greetings:
		var greeting: DialogueGreeting = item as DialogueGreeting
		if greeting == null or greeting.text.is_empty():
			continue
		any_text.append(greeting)
		if is_greeting_eligible(greeting, band, mood, period, keys):
			eligible.append(greeting)

	var layer: String = "eligible"
	var pool: Array = eligible
	if pool.is_empty():
		layer = "any_eligible"
		pool = any_text
	if pool.is_empty():
		return {
			"id": "greeting:generated", "text": GENERATED_GREETING_TEXT,
			"fallback": "generated", "resource": null,
		}

	var chosen: DialogueGreeting = _weighted_pick(pool, seed_value) as DialogueGreeting
	if chosen == null:
		return {
			"id": "greeting:generated", "text": GENERATED_GREETING_TEXT,
			"fallback": "generated", "resource": null,
		}
	return {
		"id": chosen.id, "text": chosen.text, "fallback": layer, "resource": chosen,
	}


## --- Response selection / fallback (ticket 023) ------------------------------

## Generated line used only when no authored response of any layer exists.
const GENERATED_RESPONSE_TEXT: String = "I'm not sure what to say about that."


## Select an authored response through the layered fallback chain:
##   exact (topic + outcome + band) -> topic default -> partial topic match ->
##   generic authored line -> generated line.
## `outcome` is "success"/"failure" from the roll; `band` is the responder's
## derived relationship type toward the speaker. Empty key arrays are wildcards,
## so a partial match (e.g. outcome only) still beats a generic line.
static func select_response(
	responses: Array,
	topic_id: String,
	outcome: String,
	band: String,
	seed_value: int = -1
) -> Dictionary:
	var exact: Array = []
	var topic_default: Array = []
	var topic_partial: Array = []
	var generic: Array = []

	for item in responses:
		var response: DialogueResponse = item as DialogueResponse
		if response == null or response.text.is_empty():
			continue
		var outcome_keyed: bool = not response.outcomes.is_empty()
		var band_keyed: bool = not response.relationship_bands.is_empty()
		var outcome_matches: bool = not outcome_keyed or response.outcomes.has(outcome)
		var band_matches: bool = not band_keyed or response.relationship_bands.has(band)

		if response.topic_id == topic_id and outcome_keyed and band_keyed and outcome_matches and band_matches:
			exact.append(response)
		elif response.topic_id == topic_id and not outcome_keyed and not band_keyed:
			topic_default.append(response)
		elif response.topic_id == topic_id and outcome_matches and band_matches:
			topic_partial.append(response)
		elif response.topic_id.is_empty() and outcome_matches and band_matches:
			generic.append(response)

	var layers: Array = [
		["exact", exact],
		["topic_default", topic_default],
		["topic_partial", topic_partial],
		["generic_authored", generic],
	]
	for layer in layers:
		var pool: Array = layer[1]
		if pool.is_empty():
			continue
		var chosen: DialogueResponse = _seeded_pick(pool, seed_value) as DialogueResponse
		if chosen == null:
			continue
		return {
			"id": chosen.id, "text": chosen.text,
			"fallback": str(layer[0]), "resource": chosen,
		}

	return {
		"id": "response:generated", "text": GENERATED_RESPONSE_TEXT,
		"fallback": "generated", "resource": null,
	}


## True when a reply option may be offered to this pair. Replies are keyed by
## topic_id at selection time (outcome/band do not exist yet), so the only gates
## are the optional trait/mood/interest fields on DialogueResponse.
static func is_reply_eligible(
	response: DialogueResponse,
	speaker: NpcInstance,
	listener: NpcInstance,
	speaker_template: CharacterTemplate,
	listener_template: CharacterTemplate
) -> bool:
	if response == null or response.text.is_empty() or response.is_line_only():
		return false
	if speaker == null or listener == null:
		return false
	if response.min_mood > 0 and speaker.mood < response.min_mood:
		return false
	if response.max_mood < 100 and speaker.mood > response.max_mood:
		return false
	var keys: Array[String] = _trait_keys(speaker_template)
	keys.append_array(_trait_keys(listener_template))
	if not _contains_all(response.required_traits, keys):
		return false
	if not _contains_all(response.required_interests, keys):
		return false
	return true


## Seeded pool of 2–3 rollable reply options for an NPC-initiated talk. Returns
## an empty array when the author supplied none for the topic (the caller then
## ends the interaction rather than dead-ending with a fake choice).
static func build_reply_pool(
	responses: Array,
	topic_id: String,
	speaker: NpcInstance,
	listener: NpcInstance,
	speaker_template: CharacterTemplate,
	listener_template: CharacterTemplate,
	seed_value: int = -1,
	min_size: int = 2,
	max_size: int = 3
) -> Array:
	var eligible: Array = []
	for item in responses:
		var response: DialogueResponse = item as DialogueResponse
		if response == null or response.topic_id != topic_id:
			continue
		if is_reply_eligible(response, speaker, listener, speaker_template, listener_template):
			eligible.append(response)
	if eligible.is_empty():
		return []

	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.seed = Time.get_ticks_usec()
	_shuffle(rng, eligible)
	var size: int = clampi(rng.randi_range(mini(min_size, max_size), maxi(min_size, max_size)), 1, eligible.size())
	return eligible.slice(0, size)


## --- Seeded selection helpers ------------------------------------------------

## Seeded weighted pick over greetings. A weight <= 0 is excluded while any
## positive weight exists; if every weight is <= 0 the pick is uniform, so a
## fully disabled authoring set still opens a conversation.
static func _weighted_pick(pool: Array, seed_value: int) -> Resource:
	if pool.is_empty():
		return null
	var use_weights: bool = false
	var total: float = 0.0
	for item in pool:
		var greeting: DialogueGreeting = item as DialogueGreeting
		if greeting != null and greeting.weight > 0.0:
			use_weights = true
			total += greeting.weight
	if not use_weights:
		total = float(pool.size())

	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.seed = Time.get_ticks_usec()
	var roll: float = rng.randf_range(0.0, total)
	var fallback: Resource = pool[0] as Resource
	for item in pool:
		var greeting: DialogueGreeting = item as DialogueGreeting
		if greeting == null:
			continue
		var weight: float = 1.0 if not use_weights else maxf(0.0, greeting.weight)
		if weight > 0.0:
			fallback = greeting
		roll -= weight
		if roll < 0.0 and weight > 0.0:
			return greeting
	return fallback


static func _seeded_pick(pool: Array, seed_value: int) -> Resource:
	if pool.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.seed = Time.get_ticks_usec()
	return pool[rng.randi_range(0, pool.size() - 1)] as Resource
