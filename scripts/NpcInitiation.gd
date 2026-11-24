class_name NpcInitiation
extends RefCounted

## NpcInitiation
##
## Pure, scene-tree-free decision helpers for NPC-initiated interactions (ticket 016).
## Given an initiator instance/target instance pair and their authored templates, it
## scores outgoingness, decides whether an NPC may initiate, weights possible targets
## and makes seeded random picks. Nothing here touches the scene tree, autoload globals,
## an instance's meters (reads only) or the dialogue resolution pipeline — ticket 014's
## `DialogueFilter` builds the eligible pool and ticket 015's `DialogueResolver` applies
## every delta. Keeping these decisions pure makes the whole initiation path headless-
## testable and leaves `Game.gd` with only scene-side wiring.
##
## All randomness is driven by a caller-supplied seed so a day can be reproduced in
## verification; play passes a seed derived from the day number and an attempt counter.


## Minimum outgoingness score required to initiate a conversation.
const MIN_OUTGOINGNESS: int = 1

## Trait ids/tags that make a character more likely to initiate or be approached.
## Ids and tags are matched case-insensitively via the same key set as DialogueFilter.
const POSITIVE_KEYS: Array = [
	"trait:outgoing", "outgoing", "sociable", "extrovert", "extroverted",
]
## Trait ids/tags that reduce the score. "social"/"quiet" are deliberately absent:
## `trait_shy.tres` carries "social" as a tag, so matching it would cancel the shyness
## of the authored player template.
const NEGATIVE_KEYS: Array = [
	"trait:shy", "shy", "introvert", "introverted", "reserved",
]

## Base weight every eligible target receives before the additive bonuses.
const BASE_TARGET_WEIGHT: float = 1.0
## Weight per 10 points of the initiator's directed familiarity toward the target.
const FAMILIARITY_WEIGHT: float = 1.0
## Weight per point of the target's (positive) outgoingness score.
const OUTGOING_WEIGHT: float = 2.0
## Peak weight from proximity, falling off linearly to zero at PROXIMITY_RADIUS.
const PROXIMITY_WEIGHT: float = 4.0
## Distance in pixels at which the proximity bonus reaches zero. Proximity is a
## weight, not an exclusion, so distant characters remain eligible (pair-agnostic).
const PROXIMITY_RADIUS: float = 160.0


## Outgoingness score of `template`: distinct positive keys minus distinct negative
## ones. Keys come from DialogueFilter.trait_keys() (trait ids AND tags), so modded
## traits work without code changes. A null template scores 0 and fails closed.
static func outgoingness(template: CharacterTemplate) -> int:
	if template == null:
		return 0
	var unique_keys: Dictionary = {}
	for key_variant in DialogueFilter.trait_keys(template):
		var key: String = str(key_variant).strip_edges().to_lower()
		if not key.is_empty():
			unique_keys[key] = true

	var positive: int = 0
	var negative: int = 0
	for key in unique_keys:
		if POSITIVE_KEYS.has(key):
			positive += 1
		elif NEGATIVE_KEYS.has(key):
			negative += 1
	return positive - negative


## True when `instance` may start an interaction. `conversation_busy` and
## `forced_travel` are the only blockers: an ordinary free-time hangout goal does
## not count as busy, because free-time NPCs almost always have one (user-approved).
static func can_initiate(
	instance: NpcInstance,
	template: CharacterTemplate,
	conversation_busy: bool = false,
	forced_travel: bool = false
) -> bool:
	if instance == null or outgoingness(template) < MIN_OUTGOINGNESS:
		return false
	return not conversation_busy and not forced_travel


## Initiator's directed familiarity toward `other_id`, read without creating a
## meter (filtering/initiation must never mutate relationship state).
static func familiarity_toward(instance: NpcInstance, other_id: String) -> int:
	if instance == null or other_id.is_empty():
		return 0
	var raw: Variant = instance.meters.get(other_id, null)
	return int((raw as Dictionary).get("familiarity", 0)) if raw is Dictionary else 0


## Weight for `target` as a conversation partner. Higher familiarity, an outgoing
## target and physical closeness all make a candidate more likely. Shy targets do
## not get a negative weight (clamped at 0) so they remain pickable.
static func target_weight(
	initiator: NpcInstance,
	target: NpcInstance,
	initiator_template: CharacterTemplate,
	target_template: CharacterTemplate,
	from: Vector2,
	to: Vector2
) -> float:
	if initiator == null or target == null or target.instance_id == initiator.instance_id:
		return 0.0

	var familiarity: int = familiarity_toward(initiator, target.instance_id)
	var target_outgoing: int = maxi(0, outgoingness(target_template))
	var proximity: float = 0.0
	if PROXIMITY_RADIUS > 0.0:
		var distance: float = from.distance_to(to)
		if distance < PROXIMITY_RADIUS:
			proximity = (1.0 - distance / PROXIMITY_RADIUS) * PROXIMITY_WEIGHT

	return (
		BASE_TARGET_WEIGHT
		+ float(familiarity) / 10.0 * FAMILIARITY_WEIGHT
		+ float(target_outgoing) * OUTGOING_WEIGHT
		+ proximity
	)


## Seeded weighted pick from an Array of `{ "id": String, "weight": float }`.
## Returns "" for an empty/all-zero-weight list. Non-Dictionary entries are ignored.
static func select_target(candidates: Array, seed_value: int) -> String:
	var total: float = 0.0
	for entry in candidates:
		if entry is Dictionary:
			total += maxf(0.0, float((entry as Dictionary).get("weight", 0.0)))
	if total <= 0.0:
		return ""

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var roll: float = rng.randf_range(0.0, total)
	var last_valid: String = ""
	for entry in candidates:
		if not (entry is Dictionary):
			continue
		var dictionary: Dictionary = entry
		var weight: float = maxf(0.0, float(dictionary.get("weight", 0.0)))
		var id: String = str(dictionary.get("id", ""))
		if not id.is_empty():
			last_valid = id
		roll -= weight
		if roll < 0.0 and not id.is_empty():
			return id
	return last_valid


## Seeded single random pick from a pool of DialogueTopic resources. Returns null
## for an empty pool (no eligible topics is a normal, non-crashing outcome).
static func pick_topic(pool: Array, seed_value: int) -> DialogueTopic:
	if pool.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var index: int = rng.randi_range(0, pool.size() - 1)
	return pool[index] as DialogueTopic


## Seeded Fisher–Yates ordering of ids. Used to decide which eligible initiator gets
## first pick in a check, so multiple concurrent initiations stay reproducible.
static func seeded_order(ids: Array, seed_value: int) -> Array:
	var result: Array = ids.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(result.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = result[i]
		result[i] = result[j]
		result[j] = tmp
	return result
