class_name NpcAi
extends RefCounted

## NpcAi
##
## Pure, scene-tree-free goal selection for free-time NPC behaviour (ticket 013).
## Given an instance, its authored template, a map and a seed, it picks a hangout
## destination from the NPC's interest traits and mood. Nothing here touches the
## scene tree or autoload globals, so it can be exercised from a headless script.
##
## Ticket 032 wires `relationship_candidates()` into that same weighted pick:
## directed familiarity/affection meters make NPCs seek friends and love interests
## (including the player) and avoid enemies, without complex negotiation. A
## relationship target's hangout is its active `current_goal` marker when that
## marker still exists, otherwise a stable fallback over the map's markers.

## Weight added to a hangout whose tags match one of the NPC's interests.
const INTEREST_MATCH_WEIGHT: int = 3
## Extra weight for a quiet hangout when the NPC's mood is low.
const LOW_MOOD_QUIET_WEIGHT: int = 2
## Extra weight for an interest-matched hangout when mood is high.
const HIGH_MOOD_INTEREST_WEIGHT: int = 2
## Mood below this counts as "low".
const LOW_MOOD_THRESHOLD: int = 40
## Mood at or above this counts as "high".
const HIGH_MOOD_THRESHOLD: int = 60

## Meter thresholds mirror DialogueResolver's relationship types so the AI and
## dialogue agree on who is a friend, lover or enemy. The mutual-romance template
## gate is deliberately not applied: this pure hook has no template input.
const REL_FRIEND_FAM: int = DialogueResolver.REL_FRIEND_FAM
const REL_FRIEND_AFF: int = DialogueResolver.REL_FRIEND_AFF
const REL_LOVER_FAM: int = DialogueResolver.REL_LOVER_FAM
const REL_LOVER_AFF: int = DialogueResolver.REL_LOVER_AFF
const REL_ENEMY_AFF: int = DialogueResolver.REL_ENEMY_AFF

## Weight added to the hangout of a Friend / Lover target.
const SEEK_FRIEND_WEIGHT: int = 5
const SEEK_LOVER_WEIGHT: int = 8
## Added to an Enemy target's hangout. A negative effective weight keeps the
## destination out of the roll while any positive candidate exists; if every
## candidate is negative, the v1 base weights are restored so play never stalls.
const AVOID_ENEMY_WEIGHT: int = -100
## Default player instance id; the player has no hangout marker, so its position
## is used as the destination instead. Callers with a configured player id pass
## it as `select_goal()`'s optional `player_id` argument.
const PLAYER_ID: String = "player"


## Select a free-time goal for `instance`.
##
## Returns { "goal": String, "destination": Vector2 }. `goal` is empty when the
## map authors no hangout markers and no relationship candidate has a position.
## `seed_value` is normally the day/period and `eval_count` increments per
## re-evaluation, making a given NPC's choice reproducible across runs.
##
## `all_instances` is the live roster (NPCs plus the player); an empty roster
## reproduces v1's interest/mood selection exactly.
static func select_goal(
	instance: NpcInstance,
	template: CharacterTemplate,
	map: Map,
	seed_value: int,
	eval_count: int,
	all_instances: Array = [],
	player_id: String = PLAYER_ID
) -> Dictionary:
	var no_goal: Dictionary = {"goal": "", "destination": Vector2.ZERO}
	if instance == null or map == null:
		return no_goal

	var hangouts: Array = map.get_hangout_marker_names()
	var relationship_weights: Dictionary = _relationship_weights_by_key(
		instance, all_instances, hangouts, map, player_id
	)
	if hangouts.is_empty() and relationship_weights.is_empty():
		return no_goal

	var interest_keys: Dictionary = _interest_keys(template)
	var candidates: Array = []
	var total_base_weight: int = 0

	for marker_name_variant in hangouts:
		var marker_name: String = str(marker_name_variant)
		var tags: PackedStringArray = map.get_hangout_interests(marker_name)
		var matches_interest: bool = false
		var is_quiet: bool = false
		for tag_variant in tags:
			var tag: String = str(tag_variant)
			if interest_keys.has(tag):
				matches_interest = true
			if tag == "quiet":
				is_quiet = true

		var base_weight: int = 1
		if matches_interest:
			base_weight += INTEREST_MATCH_WEIGHT
			if instance.mood >= HIGH_MOOD_THRESHOLD:
				base_weight += HIGH_MOOD_INTEREST_WEIGHT
		if is_quiet and instance.mood < LOW_MOOD_THRESHOLD:
			base_weight += LOW_MOOD_QUIET_WEIGHT

		var destination_variant: Variant = map.get_marker(marker_name, map.spawn_point)
		var destination: Vector2 = destination_variant if destination_variant is Vector2 else map.spawn_point
		var delta: int = int(relationship_weights.get(marker_name, 0))
		candidates.append({
			"goal": "hangout:%s" % marker_name,
			"destination": destination,
			"base_weight": base_weight,
			"weight": base_weight + delta,
		})
		total_base_weight += base_weight

	# The player has no hangout marker, so its current position is the candidate.
	for key_variant in relationship_weights.keys():
		var key: String = str(key_variant)
		if not key.begins_with("player:"):
			continue
		var target_id: String = key.substr("player:".length())
		var delta: int = int(relationship_weights[key])
		# An avoided player has no separate safe destination: using its position
		# would make the NPC walk toward the enemy it is meant to avoid.
		if delta <= 0:
			continue
		var destination: Vector2 = _position_for(all_instances, target_id, map.spawn_point)
		var goal: String = ("seek:" if delta > 0 else "avoid:") + target_id
		candidates.append({
			"goal": goal,
			"destination": destination,
			"base_weight": 1,
			"weight": 1 + delta,
		})
		total_base_weight += 1

	var positive_total: int = 0
	for candidate_variant in candidates:
		var candidate: Dictionary = candidate_variant as Dictionary
		positive_total += maxi(0, int(candidate["weight"]))
	# An all-enemy roster leaves no positive weight. Fall back to v1's base
	# weights rather than returning no goal: the enemy destination can then be
	# chosen only when nothing else qualifies.
	var use_base_weights: bool = positive_total <= 0
	var roll_total: int = total_base_weight if use_base_weights else positive_total
	if roll_total <= 0:
		return no_goal

	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(instance.instance_id, seed_value, eval_count)
	var roll: int = rng.randi_range(0, roll_total - 1)
	var chosen: Dictionary = candidates[0]
	for candidate_variant in candidates:
		var candidate: Dictionary = candidate_variant as Dictionary
		var weight: int = int(candidate["base_weight"]) if use_base_weights else maxi(0, int(candidate["weight"]))
		roll -= weight
		if roll < 0:
			chosen = candidate
			break

	var chosen_destination: Variant = chosen["destination"]
	var destination: Vector2 = chosen_destination if chosen_destination is Vector2 else map.spawn_point
	return {"goal": str(chosen["goal"]), "destination": destination}


## Preference keys contributed by the template's traits. Both the stable trait
## id (e.g. "trait:likes_sports") and its tags (e.g. "sports") are included so a
## modder can match either without code changes. Authored characters express
## preferences through `interest`, `skill` and `personality` traits (e.g. Riley's
## studious/skill trait supplies "academic"/"study"); only `dislike` traits are
## excluded, so all four authored hangouts are reachable by interest weighting.
static func _interest_keys(template: CharacterTemplate) -> Dictionary:
	var keys: Dictionary = {}
	if template == null:
		return keys
	for trait_variant in template.traits:
		var trait_res: Trait = trait_variant as Trait
		if trait_res == null or trait_res.category == "dislike":
			continue
		if not trait_res.id.is_empty():
			keys[trait_res.id] = true
		for tag_variant in trait_res.tags:
			var tag: String = str(tag_variant)
			if not tag.is_empty():
				keys[tag] = true
	return keys


## Stable, reproducible seed for one NPC's n-th re-evaluation in a day.
static func _seed_for(instance_id: String, seed_value: int, eval_count: int) -> int:
	var base: int = instance_id.hash()
	return (base ^ (seed_value * 7919) ^ (eval_count * 104729)) & 0x7FFFFFFFFFFFFFFF


## Directed relationship candidates for `instance`, classified with the same
## numeric thresholds as DialogueResolver.relationship_type(). Returns an empty
## array for empty/malformed meters and ignores self and duplicate roster ids.
static func relationship_candidates(instance: NpcInstance, all_instances: Array) -> Array:
	var candidates: Array = []
	if instance == null or all_instances.is_empty():
		return candidates
	var seen: Dictionary = {}
	for entry in all_instances:
		if not (entry is NpcInstance):
			continue
		var other: NpcInstance = entry as NpcInstance
		if other == null or other == instance:
			continue
		if other.instance_id.is_empty() or seen.has(other.instance_id):
			continue
		seen[other.instance_id] = true
		var raw: Variant = instance.meters.get(other.instance_id, null)
		var meter: Dictionary = raw if raw is Dictionary else {}
		var familiarity: int = int(meter.get("familiarity", 0))
		var affection: int = int(meter.get("affection", 0))
		var relationship: String = ""
		var weight: int = 0
		if familiarity >= REL_LOVER_FAM and affection >= REL_LOVER_AFF:
			relationship = DialogueResolver.TYPE_LOVER
			weight = SEEK_LOVER_WEIGHT
		elif affection <= REL_ENEMY_AFF:
			relationship = DialogueResolver.TYPE_ENEMY
			weight = AVOID_ENEMY_WEIGHT
		elif familiarity >= REL_FRIEND_FAM and affection >= REL_FRIEND_AFF:
			relationship = DialogueResolver.TYPE_FRIEND
			weight = SEEK_FRIEND_WEIGHT
		else:
			continue
		candidates.append({
			"id": other.instance_id,
			"instance": other,
			"relationship": relationship,
			"weight": weight,
			"familiarity": familiarity,
			"affection": affection,
		})
	return candidates


## Map each relationship candidate to a weight delta keyed by hangout marker
## name, or by "player:<id>" for the player's position-based candidate.
static func _relationship_weights_by_key(
	instance: NpcInstance, all_instances: Array, hangouts: Array, map: Map, player_id: String
) -> Dictionary:
	var weights: Dictionary = {}
	for entry in relationship_candidates(instance, all_instances):
		var candidate: Dictionary = entry as Dictionary
		var target_variant: Variant = candidate.get("instance", null)
		if not (target_variant is NpcInstance):
			continue
		var target: NpcInstance = target_variant as NpcInstance
		if target == null:
			continue
		var delta: int = int(candidate.get("weight", 0))
		if delta == 0:
			continue
		var key: String = ""
		if target.instance_id == player_id:
			key = "player:%s" % target.instance_id
		else:
			key = _candidate_hangout(target, hangouts, map)
			if key.is_empty():
				continue
		weights[key] = int(weights.get(key, 0)) + delta
	return weights


## The hangout a relationship target is associated with: its active hangout
## goal when that marker still exists on the map, otherwise a stable fallback
## over the authored markers. No authored map data is needed for the fallback.
static func _candidate_hangout(target: NpcInstance, hangouts: Array, map: Map) -> String:
	var goal: String = target.current_goal
	if goal.begins_with("hangout:"):
		var marker_name: String = goal.substr("hangout:".length())
		if hangouts.has(marker_name) and map.has_marker(marker_name):
			return marker_name
	if hangouts.is_empty():
		return ""
	return str(hangouts[posmod(target.instance_id.hash(), hangouts.size())])


## World position of the player instance in the live roster.
static func _position_for(all_instances: Array, instance_id: String, fallback: Vector2) -> Vector2:
	for entry in all_instances:
		if not (entry is NpcInstance):
			continue
		var other: NpcInstance = entry as NpcInstance
		if other != null and other.instance_id == instance_id:
			return other.position
	return fallback
