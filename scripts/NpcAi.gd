class_name NpcAi
extends RefCounted

## NpcAi
##
## Pure, scene-tree-free goal selection for free-time NPC behaviour (ticket 013).
## Given an instance, its authored template, a map and a seed, it picks a hangout
## destination from the NPC's interest traits and mood. Nothing here touches the
## scene tree or autoload globals, so it can be exercised from a headless script.
##
## Relationship-driven goals (seek friends/love interests, avoid enemies) are
## deliberately deferred to dialogue tickets 014/015: directed `meters` are empty
## until those tickets populate them. `relationship_candidates()` is the seam.

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


## Select a free-time goal for `instance`.
##
## Returns { "goal": String, "destination": Vector2 }. `goal` is empty when the
## map authors no hangout markers. `seed_value` is normally the day/period and
## `eval_count` increments per re-evaluation, making a given NPC's choice
## reproducible across runs.
static func select_goal(
	instance: NpcInstance,
	template: CharacterTemplate,
	map: Map,
	seed_value: int,
	eval_count: int
) -> Dictionary:
	var no_goal: Dictionary = {"goal": "", "destination": Vector2.ZERO}
	if instance == null or map == null:
		return no_goal

	var hangouts: Array = map.get_hangout_marker_names()
	if hangouts.is_empty():
		return no_goal

	var interest_keys: Dictionary = _interest_keys(template)
	var candidates: Array = []
	var total_weight: int = 0

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

		var weight: int = 1
		if matches_interest:
			weight += INTEREST_MATCH_WEIGHT
			if instance.mood >= HIGH_MOOD_THRESHOLD:
				weight += HIGH_MOOD_INTEREST_WEIGHT
		if is_quiet and instance.mood < LOW_MOOD_THRESHOLD:
			weight += LOW_MOOD_QUIET_WEIGHT

		candidates.append({"name": marker_name, "weight": weight})
		total_weight += weight

	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(instance.instance_id, seed_value, eval_count)
	var roll: int = rng.randi_range(0, maxi(0, total_weight - 1))
	var chosen: String = str(candidates[0]["name"])
	for candidate in candidates:
		roll -= int(candidate["weight"])
		if roll < 0:
			chosen = str(candidate["name"])
			break

	var destination_variant: Variant = map.get_marker(chosen, map.spawn_point)
	var destination: Vector2 = destination_variant if destination_variant is Vector2 else map.spawn_point
	return {"goal": "hangout:%s" % chosen, "destination": destination}


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


## Seam for tickets 014/015. Relationship-meter driven goals (seek friends /
## love interests, avoid enemies) return an empty set in v1 because directed
## meters are empty until the dialogue tickets populate them.
static func relationship_candidates(_instance: NpcInstance, _all_instances: Array) -> Array:
	return []
