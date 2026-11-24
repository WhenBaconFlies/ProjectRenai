class_name NpcInstance
extends Resource

## NpcInstance
##
## Per-save runtime state for one character. Authored templates (CharacterTemplate)
## are shared and immutable; an instance owns the mutable state that diverges
## during play: stats, mood, directed relationship meters, its daily schedule,
## position and current goal. Instances reference their template by a stable
## `template_id` string, never by path or UID, so saves survive template moves.
##
## v1 uses this single shape for NPCs; later tickets reuse it for the player.
## `tier` and `coarse_position` are runtime-only chunk-loading state (ticket 019)
## and are deliberately NOT exported, so ResourceSaver does not persist them —
## ticket 017 recomputes both from the player's position on load.


## --- Chunk-loading tier constants (post-v1) --------------------------------

const TIER_CLOSE: String = "close"
const TIER_NEAR: String = "near"
const TIER_FAR: String = "far"


## --- Identity ---------------------------------------------------------------

## Stable instance id used as the TimeManager roster/record key (e.g. "npc:0").
## This is distinct from the template id: two NPCs may share one template.
@export var instance_id: String = ""

## Stable id of the authored CharacterTemplate this instance was created from.
@export var template_id: String = ""

## Cached display name, copied from the template at spawn for UI/log convenience.
@export var display_name: String = ""


## --- Mutable runtime state --------------------------------------------------

## Current stats (base + deltas): strength, dexterity, constitution,
## intelligence, wisdom, charisma. Kept as a Dictionary so later tickets can add
## stats without a schema migration, matching the spec's data-first approach.
@export var stats: Dictionary = {}

## Numeric mood, 0..100. Affects dialogue eligibility and stat checks (014/015).
@export var mood: int = 50

## Per-instance directed meters: { other_id -> { familiarity: int, affection: int } }.
@export var meters: Dictionary = {}

## Per-instance schedule: { period:int -> marker_name:String }. Marker names are
## resolved against Map.markers (see NpcSpawner / Game period-change wiring).
@export var schedule: Dictionary = {}

## World-space position. Authoritative instance position; the scene node mirrors it.
@export var position: Vector2 = Vector2.ZERO

## Active free-time goal, structured as "hangout:<marker_name>" (ticket 013).
## Empty while the NPC is idle or in class.
@export var current_goal: String = ""

## World-space destination of `current_goal`. Exported so ticket 017 can restore
## an in-flight goal instead of silently dropping it on load.
@export var goal_destination: Vector2 = Vector2.ZERO


## --- Runtime-only (not persisted) ------------------------------------------

## Chunk-loading tier. Unexported so it stays out of saves; recomputed on load.
var tier: String = TIER_CLOSE

## Runtime-only position used by far-tier coarse (straight-line) simulation and
## as the interpolation start point when a promoted NPC becomes visible again.
## Mirrors `position` while far; excluded from snapshot() with `tier`.
var coarse_position: Vector2 = Vector2.ZERO


## --- Construction -----------------------------------------------------------

## Build a fresh instance from an authored template. Stats are copied (not
## referenced) so per-instance growth never mutates the shared template.
static func from_template(template: CharacterTemplate, p_instance_id: String) -> NpcInstance:
	var instance := NpcInstance.new()
	instance.instance_id = p_instance_id
	if template == null:
		push_warning("NpcInstance.from_template: null template for '%s'" % p_instance_id)
		return instance

	instance.template_id = template.id
	instance.display_name = template.display_name
	instance.stats = {
		"strength": template.strength,
		"dexterity": template.dexterity,
		"constitution": template.constitution,
		"intelligence": template.intelligence,
		"wisdom": template.wisdom,
		"charisma": template.charisma,
	}
	return instance


## --- Stat / meter helpers ---------------------------------------------------

func get_stat(stat_name: String) -> int:
	return int(stats.get(stat_name, 0))


func set_stat(stat_name: String, value: int) -> void:
	stats[stat_name] = clampi(value, 0, 100)


## Return the directed meter toward `other_id`, creating a zeroed one on first
## access so callers in 014/015 can mutate it directly.
func get_meter(other_id: String) -> Dictionary:
	if not meters.has(other_id):
		meters[other_id] = {"familiarity": 0, "affection": 0}
	var meter: Variant = meters[other_id]
	if not (meter is Dictionary):
		meters[other_id] = {"familiarity": 0, "affection": 0}
	return meters[other_id]


## --- Schedule helpers -------------------------------------------------------

## Marker name scheduled for `period` (1..4), or "" when none is authored.
func marker_for_period(period: int) -> String:
	return str(schedule.get(period, ""))


func set_marker_for_period(period: int, marker_name: String) -> void:
	schedule[period] = marker_name


## --- Template linkage -------------------------------------------------------

## Resolve the authored template through the ModLoader registry. Returns null on
## a missing template — callers must treat that as a recoverable error.
##
## The registry node is looked up at runtime rather than via the autoload global
## identifier so this Resource script also compiles in headless `--script` main
## loops, where autoload globals are not registered at compile time.
func resolve_template() -> CharacterTemplate:
	if template_id.is_empty():
		return null
	var loader := _mod_loader()
	if loader == null:
		return null
	# Autoload globals are unavailable to --script-loaded scripts at compile time,
	# so read the bucket constant from the live autoload instead of hardcoding it.
	var bucket: Variant = loader.get("TYPE_CHARACTER")
	var bucket_name: String = str(bucket) if bucket != null else "character"
	return loader.call("get_resource", bucket_name, template_id) as CharacterTemplate


## Locate the ModLoader autoload at runtime (see resolve_template()).
static func _mod_loader() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	return loop.root.get_node_or_null(NodePath("ModLoader"))


## --- Serialization seam (ticket 017) ---------------------------------------

## Plain-Dictionary payload for a future Godot Resource save. `tier` is excluded
## on purpose: it is runtime-only and recomputed from player position on load.
func snapshot() -> Dictionary:
	return {
		"instance_id": instance_id,
		"template_id": template_id,
		"display_name": display_name,
		"stats": stats.duplicate(true),
		"mood": mood,
		"meters": meters.duplicate(true),
		"schedule": schedule.duplicate(true),
		"position": position,
		"current_goal": current_goal,
		"goal_destination": goal_destination,
	}


## Restore from a snapshot produced by snapshot(). Returns null on a malformed
## payload and never partially applies changes.
static func from_snapshot(data: Dictionary) -> NpcInstance:
	if not data.has("instance_id") or not data.has("template_id"):
		return null
	var instance := NpcInstance.new()
	instance.instance_id = str(data.get("instance_id", ""))
	instance.template_id = str(data.get("template_id", ""))
	instance.display_name = str(data.get("display_name", ""))
	var stats_data: Variant = data.get("stats", {})
	var meters_data: Variant = data.get("meters", {})
	var schedule_data: Variant = data.get("schedule", {})
	instance.stats = (stats_data as Dictionary).duplicate(true) if stats_data is Dictionary else {}
	instance.meters = (meters_data as Dictionary).duplicate(true) if meters_data is Dictionary else {}
	instance.schedule = (schedule_data as Dictionary).duplicate(true) if schedule_data is Dictionary else {}
	instance.mood = clampi(int(data.get("mood", 50)), 0, 100)
	var pos: Variant = data.get("position", Vector2.ZERO)
	instance.position = pos if pos is Vector2 else Vector2.ZERO
	instance.current_goal = str(data.get("current_goal", ""))
	var goal_pos: Variant = data.get("goal_destination", Vector2.ZERO)
	instance.goal_destination = goal_pos if goal_pos is Vector2 else Vector2.ZERO
	return instance
