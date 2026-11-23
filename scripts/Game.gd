## Game
##
## Root controller for the playable Game scene. The day clock starts here, in
## this scene's _ready(), so any scene-level listener is connected before
## TimeManager emits day_started / state_changed for day 1.
##
## Ticket 012 owns NPC lifecycle here: spawn NPCs from template ids, register
## their stable instance ids with TimeManager, provide instance-backed stats for
## the attendance/grade stub, and move NPCs to their scheduled class marker on
## period change. All of this happens BEFORE start_day() so the initial PERIOD1
## transition is observed and NPCs are seated immediately.
extends Node2D

## Roster id for the player. Mirrors TimeManager's exported default; the player
## instance shape arrives with the save/load ticket, so for now only the id and
## a template-backed stats fallback are needed.
const FALLBACK_PLAYER_ID: String = "player"


var _npcs: Array = []
var _instances_by_id: Dictionary = {}
var _map: Map = null
var _spawner: NpcSpawner = null


func _ready() -> void:
	_setup_npcs()
	_time_connect()
	# A fresh start has no save to restore. A loaded save (ticket 017) is
	# restored by that ticket instead, so never overwrite a running clock.
	if not TimeManager.is_running() and GameManager.current_save == null:
		TimeManager.start_day(1)


## --- NPC setup --------------------------------------------------------------

## Spawn NPCs under an "Npcs" node and wire their ids/stats into TimeManager.
func _setup_npcs() -> void:
	var renderer := get_node_or_null("MapRenderer") as MapRenderer
	_map = renderer.map if renderer != null else null

	var npcs_root: Node2D = get_node_or_null("Npcs") as Node2D
	if npcs_root == null:
		npcs_root = Node2D.new()
		npcs_root.name = "Npcs"
		add_child(npcs_root)

	_spawner = NpcSpawner.new()
	_npcs = _spawner.spawn(npcs_root, _map, NpcSpawner.DEFAULT_TEMPLATE_IDS)
	_instances_by_id.clear()
	for npc_variant in _npcs:
		var npc: Npc = npc_variant as Npc
		if npc != null and npc.instance != null:
			_instances_by_id[npc.instance.instance_id] = npc.instance

	# set_roster must receive stable instance ids (ticket 011 requirement), not
	# template ids — otherwise multiple NPCs from one template would collapse
	# into a single attendance record.
	TimeManager.set_roster(_player_id(), _instances_by_id.keys())
	TimeManager.set_stats_provider(Callable(self, "_stats_for"))


## Connect scene-level listeners before the clock starts.
func _time_connect() -> void:
	if not TimeManager.state_changed.is_connected(_on_state_changed):
		TimeManager.state_changed.connect(_on_state_changed)


## Current player roster id, honouring TimeManager's exported override.
func _player_id() -> String:
	var configured: String = TimeManager.player_character_id
	return configured if not configured.is_empty() else FALLBACK_PLAYER_ID


## Stats provider for the grade stub. NPC ids resolve to their instance stats;
## the player falls back to the same directly-loaded template that ticket 011
## uses. Unknown ids return an empty dict (TimeManager treats it as zero stats).
func _stats_for(id: String) -> Dictionary:
	if _instances_by_id.has(id):
		var instance: NpcInstance = _instances_by_id[id]
		return {
			"intelligence": instance.get_stat("intelligence"),
			"wisdom": instance.get_stat("wisdom"),
		}
	if id == _player_id():
		var path: String = TimeManager.player_template_path
		if not path.is_empty() and ResourceLoader.exists(path):
			var template := ResourceLoader.load(path) as CharacterTemplate
			if template != null:
				return {
					"intelligence": template.intelligence,
					"wisdom": template.wisdom,
				}
	return {}


## On entry to a class period, reposition every NPC to its scheduled marker.
## Free-time AI movement is deliberately out of scope (ticket 013).
func _on_state_changed(new_state: int, _old_state: int) -> void:
	var period: int = TimeManager.period_number_for(new_state)
	if period <= 0:
		return

	for npc_variant in _npcs:
		var npc: Npc = npc_variant as Npc
		if npc == null or npc.instance == null:
			continue
		var marker_name: String = npc.instance.marker_for_period(period)
		var target: Vector2 = _map.spawn_point if _map != null else Vector2.ZERO
		if _map != null and _map.has_marker(marker_name):
			target = _map.get_marker(marker_name)
		else:
			push_warning("Game: marker '%s' not found for %s; using spawn point" % [marker_name, npc.instance.instance_id])
		npc.move_to(target)
