class_name NpcSpawner
extends RefCounted

## NpcSpawner
##
## Testable helper that turns a list of template IDs into spawned Npc nodes and
## their backing NpcInstance resources. Template lookup goes exclusively through
## the ModLoader registry (ticket 012 decision), so both authored base templates
## and mod-added templates resolve through one API.
##
## A missing template is a recoverable error: it is logged, recorded in
## get_last_report(), and skipped without failing the rest of the spawn.

## Template ids used by the default debug day. Four distinct authored templates
## so the NPC count is deterministic regardless of which mods are enabled; the
## player's char:alex is deliberately excluded. Mod characters remain available
## to spawner callers as optional extras via the same registry.
const DEFAULT_TEMPLATE_IDS: Array = [
	"char:sam",
	"char:jordan",
	"char:riley",
	"char:taylor",
]

## Instance id prefix. Ids are stable per-save and distinct from template ids.
const INSTANCE_ID_PREFIX: String = "npc:"

## Horizontal spacing applied to NPCs at the map spawn point so they do not
## start stacked on top of each other.
const SPAWN_OFFSET_X: float = 14.0

## Spawned instances, in spawn order.
var _instances: Array = []

## Diagnostics for the most recent spawn(): one entry per requested template id.
var _report: Array = []


## Spawn one NPC per valid template id in `template_ids` (up to 5 for v1).
## `parent` receives the Npc nodes; `map` supplies the spawn point and the
## marker names used to build default schedules. Returns the spawned Npc nodes.
func spawn(parent: Node2D, map: Map, template_ids: Array) -> Array:
	_instances.clear()
	_report.clear()

	if parent == null:
		push_error("NpcSpawner.spawn: no parent node; nothing spawned")
		return []

	var spawn_point: Vector2 = map.spawn_point if map != null else Vector2.ZERO
	var marker_names: Array = map.get_marker_names() if map != null else []
	if marker_names.is_empty():
		push_warning("NpcSpawner: map has no named markers; schedules will use the spawn point")

	# Runtime lookups (not autoload globals) so this helper also compiles in
	# headless --script main loops where autoload globals are unavailable.
	var loader: Node = NpcInstance._mod_loader()
	var bucket_name: String = "character"
	if loader != null:
		var bucket: Variant = loader.get("TYPE_CHARACTER")
		if bucket != null:
			bucket_name = str(bucket)

	var spawned: Array = []
	var limit: int = mini(5, template_ids.size())
	for i in range(limit):
		var template_id: String = str(template_ids[i])
		var template: CharacterTemplate = null
		if loader != null:
			template = loader.call("get_resource", bucket_name, template_id) as CharacterTemplate
		if template == null:
			# Recoverable: skip this NPC only, keep spawning the rest.
			push_warning("NpcSpawner: missing template '%s' for slot %d; skipping" % [template_id, i])
			_report.append({
				"template_id": template_id,
				"instance_id": "",
				"status": "skipped",
				"reason": "missing template",
			})
			continue

		var instance_id: String = "%s%d" % [INSTANCE_ID_PREFIX, i]
		var instance: NpcInstance = NpcInstance.from_template(template, instance_id)
		instance.position = spawn_point + Vector2(SPAWN_OFFSET_X * float(i + 1), 0.0)
		instance.schedule = _build_schedule(marker_names, i)

		var npc := Npc.new()
		npc.name = "Npc_%s" % instance_id.replace(":", "_")
		parent.add_child(npc)
		npc.setup(instance)

		_instances.append(instance)
		spawned.append(npc)
		_report.append({
			"template_id": template_id,
			"instance_id": instance_id,
			"status": "spawned",
			"reason": "",
		})

	return spawned


## Spawned instances for the most recent spawn() call (copy).
func get_instances() -> Array:
	return _instances.duplicate()


## Diagnostics for the most recent spawn() call (deep copy).
func get_last_report() -> Array:
	return _report.duplicate(true)


## Build a deterministic period→marker schedule. Rotating by NPC index spreads
## NPCs across the available classrooms instead of stacking them in one room.
func _build_schedule(marker_names: Array, index: int) -> Dictionary:
	var schedule: Dictionary = {}
	for period in range(1, 5):
		if marker_names.is_empty():
			schedule[period] = ""
		else:
			schedule[period] = str(marker_names[(index + period - 1) % marker_names.size()])
	return schedule
