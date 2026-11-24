## Game
##
## Root controller for the playable Game scene. The day clock starts here, in
## this scene's _ready(), so any scene-level listener is connected before
## TimeManager emits day_started / state_changed for day 1.
##
## Ticket 012 owns NPC lifecycle here: spawn NPCs from template ids, register
## their stable instance ids with TimeManager, and provide instance-backed stats
## for the attendance/grade stub. Ticket 013 adds free-time AI and class travel:
## NPCs walk to their next class marker in the final seconds of free time and
## finish the walk at class start; skipped transitions still hard-snap. All of
## this happens BEFORE start_day() so the initial PERIOD1 transition is observed.
## Ticket 014 adds the player-facing dialogue trigger: a pure filter builds a
## pool, the pool UI shows it, and this script only wires the two together. No
## resolution happens here — ticket 015 consumes `dialogue_topic_selected`.
extends Node2D

## Emitted when the player picks a topic. Intentionally carries ids rather than
## node references so the pipeline stays pair-agnostic for ticket 016.
signal dialogue_topic_selected(topic: DialogueTopic, initiator_id: String, target_id: String)

## Roster id for the player. Mirrors TimeManager's exported default; the player
## instance shape arrives with the save/load ticket, so for now only the id and
## a template-backed stats fallback are needed.
const FALLBACK_PLAYER_ID: String = "player"

## Seconds before a class period starts that NPCs begin walking to their
## scheduled marker. On the large debug map classroom↔hangout walks can take up
## to ~9 s, so this gives them time to arrive near the start of class.
@export var class_travel_lead_sec: float = 8.0


var _npcs: Array = []
var _instances_by_id: Dictionary = {}
var _map: Map = null
var _spawner: NpcSpawner = null

## Player-side state for the pair-agnostic dialogue pipeline (ticket 014).
var _player_instance: NpcInstance = null
var _player_template: CharacterTemplate = null

## Conversation wiring. Only one conversation can be open at a time.
var _interaction: InteractionComponent = null
var _dialogue_ui: DialoguePoolUI = null
var _dialogue_target: Npc = null
var _dialogue_open: bool = false

## Guards the per-frame "free time nearly over" check to one departure per phase.
var _class_travel_issued: bool = false
## Set by skip_simulation_requested; consumed on the next state_changed so a
## skipped class transition hard-snaps instead of simulating the walk.
var _skip_pending: bool = false


func _ready() -> void:
	_setup_npcs()
	_setup_player_instance()
	_setup_dialogue()
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


## Build the player's instance from an authored template. Reusing NpcInstance
## keeps both sides of the dialogue pipeline the same shape and gives ticket 017
## one player resource to persist.
func _setup_player_instance() -> void:
	var instance_id: String = _player_id()
	var template_id: String = TimeManager.player_template_id
	if template_id.is_empty():
		template_id = "char:alex"

	var loader: Node = NpcInstance._mod_loader()
	if loader != null:
		var bucket: Variant = loader.get("TYPE_CHARACTER")
		var bucket_name: String = str(bucket) if bucket != null else "character"
		_player_template = loader.call("get_resource", bucket_name, template_id) as CharacterTemplate
		if _player_template == null and instance_id != template_id:
			_player_template = loader.call("get_resource", bucket_name, instance_id) as CharacterTemplate
	if _player_template == null and not TimeManager.player_template_path.is_empty():
		if ResourceLoader.exists(TimeManager.player_template_path):
			_player_template = ResourceLoader.load(TimeManager.player_template_path) as CharacterTemplate

	_player_instance = NpcInstance.from_template(_player_template, instance_id)
	if _player_instance.display_name.is_empty():
		_player_instance.display_name = "Player"
	# Both sides of a conversation must resolve through one id map so tickets
	# 015/016 can apply deltas uniformly (including player-targeted interactions).
	_instances_by_id[_player_instance.instance_id] = _player_instance


## Connect the proximity trigger and the pool UI. Missing nodes are a soft
## warning so older/stripped scenes still run (there is simply no dialogue).
func _setup_dialogue() -> void:
	_interaction = get_node_or_null("Player/InteractionComponent") as InteractionComponent
	_dialogue_ui = get_node_or_null("DialogueLayer/DialoguePoolUI") as DialoguePoolUI

	if _interaction != null:
		if not _interaction.interaction_requested.is_connected(_on_interaction_requested):
			_interaction.interaction_requested.connect(_on_interaction_requested)
	else:
		push_warning("Game: no InteractionComponent under Player; dialogue trigger disabled")

	if _dialogue_ui != null:
		if not _dialogue_ui.topic_selected.is_connected(_on_topic_selected):
			_dialogue_ui.topic_selected.connect(_on_topic_selected)
		if not _dialogue_ui.cancelled.is_connected(_on_conversation_cancelled):
			_dialogue_ui.cancelled.connect(_on_conversation_cancelled)
	else:
		push_warning("Game: no DialoguePoolUI under DialogueLayer; dialogue pool disabled")


## Open the pool for the nearest NPC in range. E works at any time of day
## (user decision); only proximity and an already-open conversation gate it.
func _on_interaction_requested(target: Npc) -> void:
	if _dialogue_open or _player_instance == null:
		return
	if _interaction == null or _dialogue_ui == null:
		return
	if target == null or not is_instance_valid(target) or target.instance == null:
		return
	if target.is_conversation_busy():
		return

	var topics: Array = []
	var loader: Node = NpcInstance._mod_loader()
	if loader != null:
		var bucket: Variant = loader.get("TYPE_DIALOGUE")
		var bucket_name: String = str(bucket) if bucket != null else "dialogue"
		topics = loader.call("get_all", bucket_name) as Array

	var pool: Array = DialogueFilter.build_pool(
		topics,
		_player_instance,
		target.instance,
		_player_template,
		target.instance.resolve_template()
	)

	_dialogue_open = true
	_dialogue_target = target
	_interaction.set_enabled(false)
	var player := get_node_or_null("Player") as Player
	if player != null:
		player.set_input_locked(true)
	target.set_conversation_busy(true)

	if pool.is_empty():
		_dialogue_ui.show_empty(_player_instance.instance_id, target.instance.instance_id)
	else:
		_dialogue_ui.show_pool(pool, _player_instance.instance_id, target.instance.instance_id)


## Selection ends the interaction. Resolution belongs to ticket 015, which
## listens for the signal; nothing is rolled or written here.
func _on_topic_selected(topic: DialogueTopic, initiator_id: String, target_id: String) -> void:
	if not _dialogue_open:
		return
	# Emit while the player and target are still locked: ticket 015 resolves the
	# topic from this signal and must see the interaction as still in progress.
	dialogue_topic_selected.emit(topic, initiator_id, target_id)
	_close_conversation()


## Cancel (or dismissing the empty fallback) ends the interaction with no pick.
func _on_conversation_cancelled() -> void:
	_close_conversation()


func _close_conversation() -> void:
	if _dialogue_ui != null:
		_dialogue_ui.hide_pool()
	var player := get_node_or_null("Player") as Player
	if player != null:
		player.set_input_locked(false)
	if is_instance_valid(_dialogue_target):
		_dialogue_target.set_conversation_busy(false)
	_dialogue_target = null
	_dialogue_open = false
	if _interaction != null:
		_interaction.set_enabled(true)


## Connect scene-level listeners before the clock starts.
func _time_connect() -> void:
	if not TimeManager.state_changed.is_connected(_on_state_changed):
		TimeManager.state_changed.connect(_on_state_changed)
	if not TimeManager.skip_simulation_requested.is_connected(_on_skip_requested):
		TimeManager.skip_simulation_requested.connect(_on_skip_requested)


## Current player roster id, honouring TimeManager's exported override.
func _player_id() -> String:
	var configured: String = TimeManager.player_character_id
	return configured if not configured.is_empty() else FALLBACK_PLAYER_ID


## True for FREETIME1/2/3. state_changed fires after TimeManager updates its
## state, so get_state_name() reflects `state`; the string check avoids depending
## on autoload enum access from a scene script.
func _is_free_time_state(state: int) -> bool:
	return state > 0 and TimeManager.get_state_name().begins_with("FREETIME")


## Issue class travel once, in the final `class_travel_lead_sec` of free time.
func _process(_delta: float) -> void:
	if _class_travel_issued or not TimeManager.is_running():
		return
	if not _is_free_time_state(TimeManager.get_state()):
		return
	var remaining: float = TimeManager.get_phase_duration() - TimeManager.get_phase_elapsed()
	if remaining > class_travel_lead_sec:
		return
	var next_period: int = _next_period_after_free_time()
	if next_period > 0:
		_issue_class_travel(next_period)


## FREETIME1 → PERIOD2, FREETIME2 → PERIOD3, FREETIME3 → PERIOD4.
func _next_period_after_free_time() -> int:
	match TimeManager.get_state_name():
		"FREETIME1":
			return 2
		"FREETIME2":
			return 3
		"FREETIME3":
			return 4
		_:
			return 0


## Point every NPC's navigation agent at its scheduled marker for `period`.
func _issue_class_travel(period: int) -> void:
	_class_travel_issued = true
	for npc_variant in _npcs:
		var npc: Npc = npc_variant as Npc
		if npc == null or npc.instance == null:
			continue
		var marker_name: String = npc.instance.marker_for_period(period)
		var target: Vector2 = _marker_position(marker_name, npc)
		npc.set_forced_destination("class:%s" % marker_name, target)


## Resolve a marker name to a world-space position, with the authored spawn
## point as a recoverable fallback (e.g. a modded map missing the marker).
func _marker_position(marker_name: String, npc: Npc) -> Vector2:
	if _map != null and _map.has_marker(marker_name):
		return _map.get_marker(marker_name)
	push_warning("Game: marker '%s' not found for %s; using spawn point" % [marker_name, npc.instance.instance_id])
	return _map.spawn_point if _map != null else Vector2.ZERO


func _on_skip_requested(_from_state: int, _to_state: int, _skipped_duration: float) -> void:
	_skip_pending = true


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


## On entry to a free-time phase, enable goal-driven AI and reset the travel
## guard. On class entry, let an already-issued class walk finish; hard-snap only
## when the transition came from skip() or the lead window was missed.
func _on_state_changed(new_state: int, _old_state: int) -> void:
	if _is_free_time_state(new_state):
		_class_travel_issued = false
		_skip_pending = false
		var seed_value: int = TimeManager.get_day_number()
		for npc_variant in _npcs:
			var active_npc: Npc = npc_variant as Npc
			if active_npc != null:
				active_npc.set_ai_enabled(true, _map, seed_value)
		return

	var was_skip: bool = _skip_pending
	_skip_pending = false

	var period: int = TimeManager.period_number_for(new_state)
	if period <= 0:
		# BREAK, DAYEND and IDLE must stop all movement (including class travel)
		# while the clock is paused.
		for npc_variant in _npcs:
			var idle_npc: Npc = npc_variant as Npc
			if idle_npc != null:
				idle_npc.set_ai_enabled(false)
		return

	for npc_variant in _npcs:
		var npc: Npc = npc_variant as Npc
		if npc == null or npc.instance == null:
			continue
		var marker_name: String = npc.instance.marker_for_period(period)
		var target: Vector2 = _marker_position(marker_name, npc)
		var goal: String = "class:%s" % marker_name
		if was_skip:
			# Skipped time is not simulated (ticket 011): snap instead of walking.
			npc.set_ai_enabled(false)
			npc.move_to(target)
		elif not npc.is_forced_to(goal):
			# The lead window was missed (e.g. a test advanced the clock in one
			# jump) — start the walk now so NPCs still travel rather than pop.
			npc.set_forced_destination(goal, target)
