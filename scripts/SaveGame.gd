class_name SaveGame
extends Resource

## SaveGame
##
## Whole-game-state payload for ticket 017. One instance is written per slot as a
## Godot text resource (`.tres`) under `user://saves/`. Every exported field is
## serialized by ResourceSaver; instances are stored as NpcInstance resources and
## link to their authored CharacterTemplate by stable `template_id` only — never
## by path or UID — so moving a template does not break a save.
##
## `version` is the forward-compatibility seam: SaveManager rejects saves written
## by a newer version before applying any state, and accepts older ones with a
## warning (v1 has no migrations to run).


## Bump only when the serialized field set changes in a way old saves cannot read.
const CURRENT_VERSION: int = 1


## Format version of this payload. Checked by SaveManager.load_slot().
@export var version: int = CURRENT_VERSION

## Unix time in milliseconds when the slot was written. Used by F9 ("load latest")
## to pick the most recent slot without relying on filesystem timestamps.
@export var saved_at: int = 0

## Sanitized slot id this resource was written to (informational/diagnostics).
@export var slot_name: String = ""

## Exact TimeManager.get_day_snapshot() payload: day, state, elapsed, attendance,
## grades, roster, player id and absence flag.
@export var day_snapshot: Dictionary = {}

## The player's runtime state. Uses the same NpcInstance shape as NPCs so the
## dialogue pipeline stays pair-agnostic (ticket 014 decision).
@export var player_instance: NpcInstance = null

## All NPC runtime state. Plain Array (not typed) for reliable `.tres` round-trips
## across Godot 4.2 headless builds; entries are NpcInstance resources.
@export var npc_instances: Array = []

## Ticket-015 save option: whether the post-interaction feedback panel is shown.
@export var show_relationship_feedback: bool = true

## Monotonic write order, assigned by SaveManager on each successful write.
## Millisecond timestamps can collide; this makes F9's "latest slot" deterministic.
@export var write_seq: int = 0


## Build a save from live state. Instances are deep-copied through their
## snapshot()/from_snapshot() seam so later gameplay mutations cannot change a
## save that is still in memory (e.g. GameManager.current_save after a load).
static func from_state(
	p_slot_name: String,
	p_day_snapshot: Dictionary,
	p_player: NpcInstance,
	p_npcs: Array,
	p_feedback: bool,
	p_write_seq: int = 0
) -> SaveGame:
	var save := SaveGame.new()
	save.version = CURRENT_VERSION
	save.saved_at = int(Time.get_unix_time_from_system() * 1000.0)
	save.slot_name = p_slot_name
	save.day_snapshot = p_day_snapshot.duplicate(true)
	save.show_relationship_feedback = p_feedback
	save.write_seq = p_write_seq

	if p_player != null:
		var player_copy: NpcInstance = NpcInstance.from_snapshot(p_player.snapshot())
		if player_copy != null:
			save.player_instance = player_copy
	for npc_variant in p_npcs:
		var npc: NpcInstance = npc_variant as NpcInstance
		if npc == null:
			continue
		var npc_copy: NpcInstance = NpcInstance.from_snapshot(npc.snapshot())
		if npc_copy != null:
			save.npc_instances.append(npc_copy)
	return save


## True when this payload can be applied by the current build. A save from the
## future is never applied; an older one is accepted with a warning (no
## migrations in v1).
func is_compatible() -> bool:
	return version > 0 and version <= CURRENT_VERSION


## Structural validation independent of version. Checked at the load gate so a
## malformed payload is rejected before the scene mutates any live state; the
## day state alone is not enough — every instance the restore path consumes must
## be present and identifiable.
func is_well_formed() -> bool:
	if not (day_snapshot is Dictionary):
		return false
	var day: Dictionary = day_snapshot as Dictionary
	if not day.has("day") or not day.has("state"):
		return false
	if player_instance == null or player_instance.instance_id.is_empty():
		return false
	if not (npc_instances is Array):
		return false
	for entry in npc_instances:
		var instance: NpcInstance = entry as NpcInstance
		if instance == null or instance.instance_id.is_empty():
			return false
	return true
