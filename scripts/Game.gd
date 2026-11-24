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
## pool, the pool UI shows it, and this script only wires the two together.
## Ticket 015 adds the resolver: this script still applies no deltas itself, it
## forwards the selection to `DialogueResolver` and shows optional feedback.
## Ticket 016 adds NPC initiation: during free time an outgoing NPC may pick a
## target (player or NPC), choose a random topic from the same filtered pool and
## emit `dialogue_topic_selected` — so resolution, deltas and feedback are shared
## with the player path and this script still applies no deltas itself.
## Ticket 017 adds save/load: this script supplies a state provider to
## SaveManager, restores player/NPC instances and the day snapshot when
## GameManager.current_save is set, and handles the F5/F9 debug hotkeys.
## Ticket 024 replaces the one-pick DialoguePoolUI with a ConversationUI overlay
## driven by the pure Conversation helper: this script owns one session at a
## time, maps numbered UI choices to conversation steps, locks input for the
## whole exchange, and gates NPC initiation behind an injectable Callable.
extends Node2D

## Emitted when the player picks a topic. Intentionally carries ids rather than
## node references so the pipeline stays pair-agnostic for ticket 016.
signal dialogue_topic_selected(topic: DialogueTopic, initiator_id: String, target_id: String)

## Emitted after a topic has been resolved, carrying the resolver's result
## Dictionary (roll breakdown, deltas, before/after meters and relationship).
signal dialogue_resolved(result: Dictionary)

## Emitted when an NPC starts an interaction on its own, before resolution.
## Carries the topic id and both roster ids; observers can count initiations
## without reaching into this script's bookkeeping.
signal npc_interaction_started(topic_id: String, initiator_id: String, target_id: String)

## Roster id for the player. Mirrors TimeManager's exported default; the player
## instance shape arrives with the save/load ticket, so for now only the id and
## a template-backed stats fallback are needed.
const FALLBACK_PLAYER_ID: String = "player"

## Seconds before a class period starts that NPCs begin walking to their
## scheduled marker. On the large debug map classroom↔hangout walks can take up
## to ~9 s, so this gives them time to arrive near the start of class.
@export var class_travel_lead_sec: float = 8.0

## Show the post-interaction meter-change panel (ticket 015 save option). On by
## default; ticket 017 persists this flag in the save payload. The runtime seam
## is set_relationship_feedback_enabled() below.
@export var show_relationship_feedback: bool = true

## --- Ticket 016: NPC-initiated interaction tuning ---------------------------

## Master switch. Verification can turn this off to isolate the player path.
@export var npc_initiation_enabled: bool = true
## How often free-time checks for a possible initiation run (seconds).
@export var npc_initiation_check_interval_sec: float = 2.0
## How long both parties stay busy/visible after an NPC-initiated interaction.
@export var npc_initiation_hold_sec: float = 2.0
## Per-initiator cooldown so one outgoing NPC cannot dominate a free-time phase.
@export var npc_initiation_cooldown_sec: float = 8.0
## An NPC-initiated talk with the player starts only inside this distance; farther
## NPCs walk over first (editor-pass decision in doc/idea-v2-decisions.md).
@export var npc_talk_radius: float = 28.0
## Give up on an approach after this long so a blocked path cannot hold the pair.
@export var npc_approach_timeout_sec: float = 6.0


var _npcs: Array = []
var _instances_by_id: Dictionary = {}
## Stable instance id -> Npc node, for freezing/unfreezing conversation parties.
var _npcs_by_id: Dictionary = {}
var _map: Map = null
var _spawner: NpcSpawner = null

## Player-side state for the pair-agnostic dialogue pipeline (ticket 014).
var _player_instance: NpcInstance = null
var _player_template: CharacterTemplate = null

## Conversation wiring (ticket 024). Only one conversation can be open at a time.
var _interaction: InteractionComponent = null
var _conversation_ui: ConversationUI = null
var _feedback_ui: InteractionFeedbackUI = null
var _dialogue_target: Npc = null
var _dialogue_open: bool = false

## The pure session owned for the duration of one conversation, plus the authored
## resource arrays and the typed action mapped to each numbered UI choice.
var _conversation: Conversation = null
var _conversation_seq: int = 0
var _conversation_npc_id: String = ""
var _topics_for_conversation: Array = []
var _greetings_for_conversation: Array = []
var _responses_for_conversation: Array = []
## Only line-only responses may be chosen as the NPC's spoken reaction in a
## player-initiated talk; rollable replies belong to the NPC-initiated pool.
var _reactions_for_conversation: Array = []
var _conversation_actions: Array = []
## Ids whose busy flags belong to the open conversation and survive a phase change.
var _conversation_locked_ids: Array = []

## NPC-initiation gate. A zero-arg Callable returning bool; tests and future cases
## (e.g. "both skipping class") can inject another condition. Invalid callables
## fall back to the free-time default in _ensure_npc_gate().
var npc_initiation_gate: Callable = Callable()

## Guards the per-frame "free time nearly over" check to one departure per phase.
var _class_travel_issued: bool = false
## Set by skip_simulation_requested; consumed on the next state_changed so a
## skipped class transition hard-snaps instead of simulating the walk.
var _skip_pending: bool = false

## --- Ticket 016 bookkeeping -------------------------------------------------

## Seconds since the last initiation check and number of checks this day (seed).
var _initiation_elapsed: float = 0.0
var _initiation_attempts: int = 0
## Ids currently locked by an NPC-initiated interaction (player id included).
var _initiation_busy: Dictionary = {}
## Initiator id -> remaining cooldown seconds.
var _initiation_cooldowns: Dictionary = {}
## Active holds: [{ initiator_id, target_id, remaining }]. Multiple are allowed;
## participants are locked individually so the same character is never double-booked.
var _active_initiations: Array = []
## NPC→player talks that are walking over before the overlay opens. Each entry is
## { initiator_id, npc, remaining, retries }; arrival opens the conversation.
var _pending_approaches: Array = []


func _ready() -> void:
	_save_connect()
	# Validate and restore the day BEFORE creating any NPC: a malformed payload
	# must fall back to a genuinely fresh day, not one where saved NPCs survive
	# with their old meters/positions (code-review finding 1).
	var loaded_save: SaveGame = GameManager.current_save as SaveGame
	if loaded_save != null:
		if (
			not loaded_save.is_well_formed()
			or not TimeManager.restore_day_snapshot(loaded_save.day_snapshot)
		):
			push_warning("Game: malformed save payload; starting a fresh day")
			GameManager.current_save = null
			loaded_save = null
			TimeManager.start_day(1)

	# A loaded save carries its own NPC instances; spawn deep copies so the
	# in-memory SaveGame in GameManager stays pristine (code-review finding 3).
	if loaded_save != null:
		_setup_npcs(_copy_instances(loaded_save.npc_instances))
	else:
		_setup_npcs()
	_setup_player_instance()
	_setup_dialogue()
	_setup_feedback()
	_setup_chunk_manager()
	_ensure_npc_gate()
	# Ticket 024: Conversation.choose_topic()/choose_reply() are the only resolvers.
	# dialogue_topic_selected is still emitted for v1 observers, but no longer
	# triggers a second roll here.
	_time_connect()
	if loaded_save != null:
		_restore_from_save(loaded_save)
	elif not TimeManager.is_running():
		TimeManager.start_day(1)


## --- NPC setup --------------------------------------------------------------

## Spawn NPCs under an "Npcs" node and wire their ids/stats into TimeManager.
## On a ticket-017 load the instances are rebuilt from the save instead of from
## template ids, preserving every per-instance field verbatim.
func _setup_npcs(p_restored_instances: Array = []) -> void:
	var renderer := get_node_or_null("MapRenderer") as MapRenderer
	_map = renderer.map if renderer != null else null

	var npcs_root: Node2D = get_node_or_null("Npcs") as Node2D
	if npcs_root == null:
		npcs_root = Node2D.new()
		npcs_root.name = "Npcs"
		add_child(npcs_root)

	_spawner = NpcSpawner.new()
	if p_restored_instances.is_empty():
		_npcs = _spawner.spawn(npcs_root, _map, NpcSpawner.DEFAULT_TEMPLATE_IDS)
	else:
		_npcs = _spawner.spawn_from_instances(npcs_root, p_restored_instances)
	_instances_by_id.clear()
	_npcs_by_id.clear()
	for npc_variant in _npcs:
		var npc: Npc = npc_variant as Npc
		if npc != null and npc.instance != null:
			_instances_by_id[npc.instance.instance_id] = npc.instance
			_npcs_by_id[npc.instance.instance_id] = npc

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


## --- Ticket 019: tiered simulation ------------------------------------------

## Hand the spawned/restored NPCs and the player focus to ChunkManager. Tiers
## are runtime-only, so this is also the recompute-on-load seam: no tier state
## is read from the save, only the player's position.
func _setup_chunk_manager() -> void:
	if ChunkManager == null:
		push_warning("Game: ChunkManager autoload missing; tiered simulation disabled")
		return
	var player_node := get_node_or_null("Player") as Node2D
	ChunkManager.setup(player_node, _npcs, _map)


## --- Ticket 017: save / load -------------------------------------------------

## Install the provider seam once the scene exists. SaveManager never reaches
## into this scene; it calls back here for the mutable per-instance state.
func _save_connect() -> void:
	if SaveManager != null and SaveManager.has_method("set_state_provider"):
		SaveManager.call("set_state_provider", Callable(self, "_provide_save_state"))


## Live state snapshot for SaveManager. The player node is authoritative for its
## current position (the instance is not mirrored every physics tick), so copy
## it in just before serialization.
func _provide_save_state() -> Dictionary:
	if _player_instance != null:
		var player_node := get_node_or_null("Player") as Node2D
		if player_node != null:
			_player_instance.position = player_node.global_position

	var npcs: Array = []
	for npc_variant in _npcs:
		var npc: Npc = npc_variant as Npc
		if npc != null and npc.instance != null:
			npcs.append(npc.instance)
	return {
		"player_instance": _player_instance,
		"npc_instances": npcs,
		"show_relationship_feedback": show_relationship_feedback,
	}


## Apply a validated SaveGame to this scene. Called only by _ready() when
## GameManager.load_slot() put a save in current_save before the scene change;
## the day snapshot was already restored there, before any NPC was created.
func _restore_from_save(save: SaveGame) -> void:
	var saved_player: NpcInstance = save.player_instance as NpcInstance
	var restored_player: NpcInstance = null
	if saved_player != null and not saved_player.instance_id.is_empty():
		# Deep copy, not an alias: dialogue/AI mutate instances during play while
		# GameManager.current_save must keep matching the file on disk.
		restored_player = NpcInstance.from_snapshot(saved_player.snapshot())
	if restored_player != null:
		_player_instance = restored_player
		_player_template = _resolve_saved_template(restored_player)
	else:
		push_warning("Game: save has no usable player instance; keeping the freshly built one")
	_warn_missing_templates()
	if _player_instance != null:
		_instances_by_id[_player_instance.instance_id] = _player_instance
		# Player._ready() queues _snap_to_spawn() before this parent _ready() runs.
		# Queue ours afterwards so the saved position wins over the map spawn.
		call_deferred("_apply_restored_player_position")

	set_relationship_feedback_enabled(save.show_relationship_feedback)
	# restore_day_snapshot() assigns state directly and emits no state_changed,
	# so AI must be synchronized explicitly (ticket-013 review finding 3).
	sync_ai_state(true)
	print("[Game] restored slot '%s': day=%d state=%s npcs=%d" % [
		save.slot_name,
		TimeManager.get_day_number(),
		TimeManager.get_state_name(),
		_npcs.size(),
	])


## Resolve a saved instance's template by stable id through the ModLoader. A
## missing template is recoverable: keep the instance and log a warning, never
## abort the load (spec acceptance criterion 7).
func _resolve_saved_template(instance: NpcInstance) -> CharacterTemplate:
	if instance == null or instance.template_id.is_empty():
		return null
	var loader: Node = NpcInstance._mod_loader()
	if loader == null:
		return null
	var bucket: Variant = loader.get("TYPE_CHARACTER")
	var bucket_name: String = str(bucket) if bucket != null else "character"
	return loader.call("get_resource", bucket_name, instance.template_id) as CharacterTemplate


## Deep copies of the saved instances via their snapshot seam, so scene-side
## mutation (meters, mood, position every physics tick) never changes the
## SaveGame resource still held by GameManager.current_save.
func _copy_instances(instances: Array) -> Array:
	var copies: Array = []
	for entry in instances:
		var instance: NpcInstance = entry as NpcInstance
		if instance == null:
			continue
		var copy: NpcInstance = NpcInstance.from_snapshot(instance.snapshot())
		if copy != null:
			copies.append(copy)
	return copies


## One diagnostic for every restored instance whose authored template is gone
## (or has an empty id). Missing templates remain recoverable — this is only the
## operator-visible warning the design promises (code-review finding 6).
func _warn_missing_templates() -> void:
	var missing: Array[String] = []
	if _player_instance != null and (
		_player_instance.template_id.is_empty() or _player_instance.resolve_template() == null
	):
		missing.append(_player_instance.instance_id)
	for npc_variant in _npcs:
		var npc: Npc = npc_variant as Npc
		if npc == null or npc.instance == null:
			continue
		var instance: NpcInstance = npc.instance
		if instance.template_id.is_empty() or instance.resolve_template() == null:
			missing.append(instance.instance_id)
	if not missing.is_empty():
		push_warning("Game: missing template for saved instance(s): %s; load continues" % ", ".join(missing))


## Runs after Player's deferred spawn snap; restores the saved world position.
func _apply_restored_player_position() -> void:
	var player_node := get_node_or_null("Player") as Node2D
	if player_node != null and _player_instance != null:
		player_node.global_position = _player_instance.position
	# Tiers were first computed from the spawn position in _setup_chunk_manager;
	# the saved player position wins once the deferred snap above has run.
	if ChunkManager != null:
		ChunkManager.set_focus(player_node)
		ChunkManager.refresh_tiers()


## Enable/disable AI from the current day state. Used both by normal state
## changes and by the load path; `preserve_saved_goals` resumes a serialized
## in-flight goal instead of rolling a new one.
func sync_ai_state(preserve_saved_goals: bool = false) -> void:
	var state: int = TimeManager.get_state()
	var free: bool = _is_free_time_state(state)
	_class_travel_issued = false
	_skip_pending = false
	_initiation_elapsed = 0.0
	var seed_value: int = TimeManager.get_day_number()
	for npc_variant in _npcs:
		var npc: Npc = npc_variant as Npc
		if npc == null:
			continue
		if free:
			npc.set_ai_enabled(true, _map, seed_value, preserve_saved_goals)
		else:
			npc.set_ai_enabled(false)


## Debug hotkeys (menus are deferred in v1). F5 writes the reserved manual slot;
## F9 loads the most recently written compatible slot.
func _unhandled_input(event: InputEvent) -> void:
	# The conversation owns input (including Esc) until it closes.
	if _dialogue_open:
		return
	if InputMap.has_action("manual_save") and event.is_action_pressed("manual_save"):
		if SaveManager.save_slot(SaveManager.MANUAL_SLOT, {}, true):
			print("[Game] manual save complete")
		else:
			push_warning("[Game] manual save failed: %s" % SaveManager.get_last_error())
	elif InputMap.has_action("manual_load") and event.is_action_pressed("manual_load"):
		GameManager.load_last_slot()


## Connect the proximity trigger and the conversation overlay. Missing nodes are
## a soft warning so stripped scenes still run (there is simply no dialogue).
func _setup_dialogue() -> void:
	_interaction = get_node_or_null("Player/InteractionComponent") as InteractionComponent
	_conversation_ui = get_node_or_null("DialogueLayer/ConversationUI") as ConversationUI

	if _interaction != null:
		if not _interaction.interaction_requested.is_connected(_on_interaction_requested):
			_interaction.interaction_requested.connect(_on_interaction_requested)
	else:
		push_warning("Game: no InteractionComponent under Player; dialogue trigger disabled")

	if _conversation_ui != null:
		if not _conversation_ui.choice_selected.is_connected(_on_conversation_choice):
			_conversation_ui.choice_selected.connect(_on_conversation_choice)
		if not _conversation_ui.cancelled.is_connected(_on_conversation_cancelled):
			_conversation_ui.cancelled.connect(_on_conversation_cancelled)
	else:
		push_warning("Game: no ConversationUI under DialogueLayer; conversations disabled")


## Public seam for ticket 028's pause gate: the conversation owns Escape while
## it is open, so the pause menu may only open when this returns false.
func is_conversation_open() -> bool:
	return _dialogue_open


## Install the default free-time gate unless a caller injected one.
func _ensure_npc_gate() -> void:
	if not npc_initiation_gate.is_valid():
		npc_initiation_gate = Callable(self, "_default_npc_initiation_gate")


func set_npc_initiation_gate(gate: Callable) -> void:
	npc_initiation_gate = gate if gate.is_valid() else Callable(self, "_default_npc_initiation_gate")


## Default condition: free time only (ticket 024). Kept behind a Callable so the
## rule can be replaced without editing Game.gd's update loop.
func _default_npc_initiation_gate() -> bool:
	return TimeManager.is_free_time_state(TimeManager.get_state())


func _npc_gate_open() -> bool:
	_ensure_npc_gate()
	return bool(npc_initiation_gate.call())


## Authored content for one conversation, read from the ModLoader registry.
func _dialogue_resources() -> Dictionary:
	var loader: Node = NpcInstance._mod_loader()
	var topics: Array = []
	var greetings: Array = []
	var responses: Array = []
	if loader != null:
		topics = loader.call("get_all", str(loader.get("TYPE_DIALOGUE"))) as Array
		greetings = loader.call("get_all", str(loader.get("TYPE_GREETING"))) as Array
		responses = loader.call("get_all", str(loader.get("TYPE_RESPONSE"))) as Array
	return {"topics": topics, "greetings": greetings, "responses": responses}


## One seed per conversation, derived from the clock and the conversation target.
func _next_conversation_seed(party_id: String) -> int:
	_conversation_seq += 1
	return (
		TimeManager.get_day_number() * 104729 + _conversation_seq * 7919 + party_id.hash()
	) & 0x7FFFFFFFFFFFFFFF


## Render one line and remember the typed action behind each numbered choice.
func _show_line(
	speaker: String, line: String, labels: Array, actions: Array, listener: String = ""
) -> void:
	_conversation_actions = actions.duplicate()
	if _conversation_ui != null:
		_conversation_ui.show_line(speaker, line, labels, listener)


## Forward a resolver payload to the existing feedback panel. The resolver's
## `initiator`/`target` keys follow the ROLL direction, which flips for an
## NPC-initiated reply (player rolls, NPC is targeted) while the session ids keep
## the conversation direction (NPC speaks, player replies).
func _show_conversation_feedback(result: Dictionary) -> void:
	if result.is_empty() or not show_relationship_feedback or _feedback_ui == null:
		return
	if _conversation == null:
		return
	var roll_initiator_id: String = _conversation.get_initiator_id()
	var roll_target_id: String = _conversation.get_target_id()
	if _conversation.is_npc_initiated():
		var swap: String = roll_initiator_id
		roll_initiator_id = roll_target_id
		roll_target_id = swap
	_feedback_ui.show_result(
		result,
		_name_for_id(roll_initiator_id),
		_name_for_id(roll_target_id)
	)


func _name_for_id(id: String) -> String:
	if id == _player_id():
		return "You"
	var instance: NpcInstance = _instances_by_id.get(id) as NpcInstance
	if instance != null and not instance.display_name.is_empty():
		return instance.display_name
	return id


func _npc_name() -> String:
	return _name_for_id(_conversation_npc_id)


## Map a numbered overlay choice to the current conversation step.
func _on_conversation_choice(index: int) -> void:
	if not _dialogue_open or _conversation == null:
		return
	if index < 0 or index >= _conversation_actions.size():
		return
	var action: Dictionary = _conversation_actions[index]
	match str(action.get("kind", "")):
		"topics":
			present_topic_pool()
		"topic":
			_resolve_topic(action.get("topic") as DialogueTopic)
		"replies":
			present_reply_pool()
		"reply":
			_resolve_reply(action.get("reply") as DialogueResponse)
		"leave":
			_close_conversation()
		_:
			push_warning("Game: unknown conversation action '%s'" % str(action.get("kind", "")))


## Locate the optional feedback panel. A stripped scene simply has no feedback.
func _setup_feedback() -> void:
	_feedback_ui = get_node_or_null("FeedbackLayer/InteractionFeedbackUI") as InteractionFeedbackUI
	if _feedback_ui == null:
		push_warning("Game: no InteractionFeedbackUI under FeedbackLayer; feedback disabled")


## Feedback save-option runtime seam (ticket 017 persists the exported flag).
func set_relationship_feedback_enabled(enabled: bool) -> void:
	show_relationship_feedback = enabled
	if not enabled and _feedback_ui != null:
		_feedback_ui.hide_feedback()


func is_relationship_feedback_enabled() -> bool:
	return show_relationship_feedback


## Open a player-initiated conversation with the nearest NPC in range. E works
## at any time of day (user decision); proximity and an open conversation gate it.
func _on_interaction_requested(target: Npc) -> void:
	if _dialogue_open or _player_instance == null:
		return
	if _interaction == null or _conversation_ui == null:
		return
	if target == null or not is_instance_valid(target) or target.instance == null:
		return
	if target.is_conversation_busy():
		return
	# Ticket 016: reject an already-claimed character BEFORE promotion. Promotion
	# mutates tier, visibility, nav target and interpolation state (review #3).
	if _initiation_busy.has(target.instance.instance_id):
		return
	# Ticket 019: only close-tier NPCs are interactable in the steady state.
	# An explicit attempt on a near/far NPC promotes it first, so a tier-update
	# lag or a zoomed-out camera never dead-ends the interaction.
	if ChunkManager != null and not ChunkManager.is_interactable(target):
		if not ChunkManager.promote_for_interaction(target):
			return

	var resources: Dictionary = _dialogue_resources()
	_conversation = Conversation.new()
	_conversation.begin_player_initiated(
		_player_instance, target.instance, _player_template,
		target.instance.resolve_template(),
		_next_conversation_seed(target.instance.instance_id),
		TimeManager.get_state_name()
	)
	_topics_for_conversation = resources.get("topics", [])
	_greetings_for_conversation = resources.get("greetings", [])
	_responses_for_conversation = resources.get("responses", [])
	_index_conversation_responses(_responses_for_conversation)
	_conversation_npc_id = target.instance.instance_id
	_dialogue_target = target
	_dialogue_open = true
	_lock_conversation_parties(target)

	var opening: Dictionary = _conversation.choose_greeting(_greetings_for_conversation)
	_show_line(
		_npc_name(), str(opening.get("text", "")), ["Continue"],
		[{"kind": "topics"}], "You"
	)


## Lock player input and the NPC party for the whole conversation. Releases happen
## only in _close_conversation(), never after a single pick.
func _lock_conversation_parties(npc: Npc, npc_id: String = "") -> void:
	var locked_id: String = npc_id if not npc_id.is_empty() else (
		npc.instance.instance_id if npc != null and npc.instance != null else ""
	)
	_conversation_locked_ids = [locked_id, _player_id()]
	_lock_initiation_party(locked_id, npc)
	_initiation_busy[_player_id()] = true
	if _interaction != null:
		_interaction.set_enabled(false)
	var player := get_node_or_null("Player") as Player
	if player != null:
		player.set_input_locked(true)


## Show the filtered 3-5 topic pool for the next player pick.
func present_topic_pool() -> void:
	if _conversation == null or not _dialogue_open:
		return
	var pool: Array = _conversation.build_topic_pool(_topics_for_conversation)
	var labels: Array = []
	var actions: Array = []
	for item in pool:
		var topic: DialogueTopic = item as DialogueTopic
		if topic == null:
			continue
		labels.append(topic.text)
		actions.append({"kind": "topic", "topic": topic})
	if labels.is_empty():
		labels.append("There is nothing to talk about right now.")
		actions.append({"kind": "leave"})
	_show_line("You", "Choose a topic:", labels, actions, _npc_name())


## Resolve one player topic, show the reactive NPC line, then either offer the
## second exchange or leave. The 023 helper performs the only roll here.
## Split the authored response registry into spoken reactions (line-only) and
## reply options (rollable). Keeps the 023 fallback chain intact while preventing
## a reply's roll fields from firing during a player-initiated reaction.
func _index_conversation_responses(responses: Array) -> void:
	_responses_for_conversation = responses.duplicate()
	_reactions_for_conversation = []
	for item in responses:
		var response: DialogueResponse = item as DialogueResponse
		if response != null and response.is_line_only():
			_reactions_for_conversation.append(response)


func _resolve_topic(topic: DialogueTopic) -> void:
	if topic == null or _conversation == null:
		return
	var result: Dictionary = _conversation.choose_topic(topic)
	if result.is_empty():
		return
	dialogue_topic_selected.emit(topic, _player_id(), _conversation_npc_id)
	dialogue_resolved.emit(result)
	_show_conversation_feedback(result)

	var reaction: Dictionary = _conversation.select_response(
		_reactions_for_conversation, _topics_for_conversation
	)
	_show_conversation_feedback(reaction)
	var line: String = str(reaction.get("response_text", reaction.get("topic_text", "")))
	if line.is_empty():
		line = "..."
	var labels: Array = ["Continue"]
	var actions: Array = [{"kind": "topics"}]
	if not _conversation.can_pick_topic():
		labels = ["Leave"]
		actions = [{"kind": "leave"}]
	_show_line(_npc_name(), line, labels, actions, "You")


## Show the fixed 2-3 filtered replies for an NPC-initiated talk. The response
## text is the player's spoken line in this shape.
func present_reply_pool() -> void:
	if _conversation == null or not _dialogue_open:
		return
	var pool: Array = _conversation.build_reply_pool(_responses_for_conversation)
	var labels: Array = []
	var actions: Array = []
	for item in pool:
		var reply: DialogueResponse = item as DialogueResponse
		if reply == null:
			continue
		labels.append(reply.text)
		actions.append({"kind": "reply", "reply": reply})
	if labels.is_empty():
		labels.append("I'm not sure what to say about that.")
		actions.append({"kind": "leave"})
	_show_line("You", "Choose your reply:", labels, actions, _npc_name())


## Resolve the player's reply (player is the roll initiator) and end the talk after
## its spoken line is acknowledged.
func _resolve_reply(reply: DialogueResponse) -> void:
	if reply == null or _conversation == null:
		return
	var result: Dictionary = _conversation.choose_reply(reply, _topics_for_conversation)
	if result.is_empty():
		return
	dialogue_resolved.emit(result)
	_show_conversation_feedback(result)
	_show_line("You", reply.text, ["Leave"], [{"kind": "leave"}], _npc_name())


## The player's template is cached at setup; NPC instances resolve theirs from
## the ModLoader registry by stable template id.
func _template_for(instance: NpcInstance, id: String) -> CharacterTemplate:
	if id == _player_id() and _player_template != null:
		return _player_template
	return instance.resolve_template()


func _display_name_for(instance: NpcInstance, id: String) -> String:
	return _name_for_id(id)


## Esc ends the conversation with no further pick.
func _on_conversation_cancelled() -> void:
	_close_conversation()


## Single close path: hide the overlay, end the helper session and release every
## lock acquired when the conversation opened.
func _close_conversation() -> void:
	if _conversation != null:
		_conversation.leave()
	if _conversation_ui != null:
		_conversation_ui.hide_panel()
	var player := get_node_or_null("Player") as Player
	if player != null:
		player.set_input_locked(false)
	if is_instance_valid(_dialogue_target):
		_dialogue_target.set_conversation_busy(false)
	for id in _conversation_locked_ids:
		_release_initiation_party(str(id))
	_conversation_locked_ids.clear()
	_conversation_actions.clear()
	_conversation = null
	_dialogue_target = null
	_conversation_npc_id = ""
	_dialogue_open = false
	if _interaction != null:
		_interaction.set_enabled(true)


## --- Ticket 016: NPC-initiated interactions --------------------------------

## One periodic check. No global one-at-a-time lock: each eligible outgoing NPC
## gets a chance, in seeded order, while a per-character busy set prevents any
## participant from being claimed twice. A skipped initiator (no target/pool) leaves
## no state behind, so an empty registry or missing topics never crashes the day.
func _try_npc_initiations() -> void:
	var topics: Array = []
	var loader: Node = NpcInstance._mod_loader()
	if loader != null:
		var bucket: Variant = loader.get("TYPE_DIALOGUE")
		var bucket_name: String = str(bucket) if bucket != null else "dialogue"
		topics = loader.call("get_all", bucket_name) as Array
	if topics.is_empty():
		return

	var initiator_ids: Array = []
	for npc_variant in _npcs:
		var candidate: Npc = npc_variant as Npc
		if candidate == null or candidate.instance == null:
			continue
		var id: String = candidate.instance.instance_id
		if _initiation_busy.has(id) or float(_initiation_cooldowns.get(id, 0.0)) > 0.0:
			continue
		if candidate.is_conversation_busy() or candidate.is_forced_destination():
			continue
		# Ticket 019: steady-state interactions are close-tier only.
		if ChunkManager != null and not ChunkManager.is_interactable(candidate):
			continue
		if not NpcInitiation.can_initiate(
			candidate.instance, candidate.instance.resolve_template(), false, false
		):
			continue
		initiator_ids.append(id)
	if initiator_ids.is_empty():
		return

	_initiation_attempts += 1
	var seed_value: int = (
		TimeManager.get_day_number() * 104729 + _initiation_attempts * 7919
	) & 0x7FFFFFFFFFFFFFFF
	for initiator_id_variant in NpcInitiation.seeded_order(initiator_ids, seed_value):
		var initiator_id: String = str(initiator_id_variant)
		var initiator: Npc = _npcs_by_id.get(initiator_id) as Npc
		if initiator == null or initiator.instance == null:
			continue
		# An earlier initiation in this same pass may have claimed this NPC.
		if _initiation_busy.has(initiator_id) or initiator.is_conversation_busy():
			continue
		_try_one_initiation(initiator, initiator_id, topics, seed_value)


## Attempt a single initiator→target interaction. All mutations are confined to
## this method; the actual roll and deltas still happen in 015's resolver listener.
func _try_one_initiation(initiator: Npc, initiator_id: String, topics: Array, seed_value: int) -> void:
	var initiator_instance: NpcInstance = initiator.instance
	var initiator_template: CharacterTemplate = initiator_instance.resolve_template()
	var initiator_position: Vector2 = initiator_instance.position

	var target_candidates: Array = []
	# The player is a valid target (unless the player's own pool is open).
	if not _dialogue_open and _player_instance != null:
		var player_id: String = _player_instance.instance_id
		if player_id != initiator_id and not _initiation_busy.has(player_id):
			var player_weight: float = NpcInitiation.target_weight(
				initiator_instance, _player_instance, initiator_template, _player_template,
				initiator_position, _player_position()
			)
			target_candidates.append({"id": player_id, "weight": player_weight})

	# Other NPCs are equally valid targets (pair-agnostic pipeline).
	for npc_variant in _npcs:
		var npc: Npc = npc_variant as Npc
		if npc == null or npc.instance == null:
			continue
		var target_id: String = npc.instance.instance_id
		if target_id == initiator_id or _initiation_busy.has(target_id):
			continue
		if npc.is_conversation_busy() or npc.is_forced_destination():
			continue
		if ChunkManager != null and not ChunkManager.is_interactable(npc):
			continue
		var weight: float = NpcInitiation.target_weight(
			initiator_instance, npc.instance, initiator_template,
			npc.instance.resolve_template(), initiator_position, npc.instance.position
		)
		target_candidates.append({"id": target_id, "weight": weight})

	var target_id: String = NpcInitiation.select_target(
		target_candidates, (seed_value + initiator_id.hash()) & 0x7FFFFFFFFFFFFFFF
	)
	if target_id.is_empty():
		return
	var target_instance: NpcInstance = _instances_by_id.get(target_id) as NpcInstance
	if target_instance == null:
		return
	# Ticket 024: only an NPC→player initiation uses the overlay and the reply
	# shape. NPC↔NPC keeps v1's immediate resolution (no player can answer).
	if target_id == _player_id():
		if initiator_position.distance_to(_player_position()) > npc_talk_radius:
			_begin_npc_approach(initiator, initiator_id)
		else:
			_begin_npc_conversation(initiator, initiator_id)
		return

	var pool: Array = DialogueFilter.build_pool(
		topics,
		initiator_instance,
		target_instance,
		initiator_template,
		_template_for(target_instance, target_id),
		(seed_value + target_id.hash()) & 0x7FFFFFFFFFFFFFFF
	)
	var topic: DialogueTopic = NpcInitiation.pick_topic(
		pool, (seed_value + target_id.hash() * 31) & 0x7FFFFFFFFFFFFFFF
	)
	if topic == null:
		return  # no eligible topics: nothing is locked, nothing is emitted

	_lock_initiation_party(initiator_id, initiator)
	_lock_initiation_party(target_id, _npcs_by_id.get(target_id) as Npc)
	_active_initiations.append({
		"initiator_id": initiator_id,
		"target_id": target_id,
		"remaining": maxf(0.1, npc_initiation_hold_sec),
	})
	_initiation_cooldowns[initiator_id] = npc_initiation_cooldown_sec

	npc_interaction_started.emit(topic.id, initiator_id, target_id)
	# NPC↔NPC has no player to answer, so it resolves immediately here. The
	# feedback panel is player-facing and is deliberately not shown for this pair.
	var result: Dictionary = DialogueResolver.resolve(
		topic, initiator_instance, target_instance, initiator_template,
		_template_for(target_instance, target_id),
		(seed_value + target_id.hash() * 31) & 0x7FFFFFFFFFFFFFFF
	)
	dialogue_topic_selected.emit(topic, initiator_id, target_id)
	if not result.is_empty():
		dialogue_resolved.emit(result)


## Start an NPC→player approach. The pair is claimed immediately so no other
## initiation can interleave, but input is not locked and the overlay stays closed
## until the NPC actually reaches the player.
func _begin_npc_approach(initiator: Npc, initiator_id: String) -> void:
	if _dialogue_open or initiator == null or initiator.instance == null:
		return
	var player_id: String = _player_id()
	if _initiation_busy.has(initiator_id) or _initiation_busy.has(player_id):
		return
	_initiation_busy[initiator_id] = true
	_initiation_busy[player_id] = true
	_initiation_cooldowns[initiator_id] = npc_initiation_cooldown_sec
	_issue_approach_destination(initiator)
	_pending_approaches.append({
		"initiator_id": initiator_id,
		"npc": initiator,
		"remaining": maxf(0.5, npc_approach_timeout_sec),
		"retries": 2,
	})


## Aim the NPC at a point just beside the player rather than on top of them.
func _issue_approach_destination(initiator: Npc) -> void:
	if initiator == null or not is_instance_valid(initiator):
		return
	var from: Vector2 = initiator.global_position
	var to: Vector2 = _player_position()
	var offset: Vector2 = from - to
	var stand_off: float = maxf(4.0, npc_talk_radius * 0.6)
	if offset.length_squared() < 0.0001:
		offset = Vector2.RIGHT
	var destination: Vector2 = to + offset.normalized() * stand_off
	initiator.set_forced_destination("talk:%s" % _player_id(), destination)


## Arrival opens the conversation; a timeout or the player walking away releases
## the pair without leaving a busy flag or forced destination behind.
func _update_approaches(delta: float) -> void:
	if _pending_approaches.is_empty():
		return
	for i in range(_pending_approaches.size() - 1, -1, -1):
		var entry: Dictionary = _pending_approaches[i]
		var npc: Npc = entry.get("npc") as Npc
		var initiator_id: String = str(entry.get("initiator_id", ""))
		if npc == null or not is_instance_valid(npc) or npc.instance == null:
			_release_approach(entry)
			_pending_approaches.remove_at(i)
			continue
		if _dialogue_open:
			# Another conversation won while this NPC was walking over.
			npc.clear_forced_destination()
			_release_approach(entry, true)
			_pending_approaches.remove_at(i)
			continue
		var distance: float = npc.global_position.distance_to(_player_position())
		if distance <= npc_talk_radius:
			entry["remaining"] = float(entry.get("remaining", 0.0)) - delta
			if not npc.is_forced_destination():
				_pending_approaches.remove_at(i)
				_begin_npc_conversation(npc, initiator_id)
			elif float(entry["remaining"]) <= 0.0:
				npc.clear_forced_destination()
				_release_approach(entry)
				_pending_approaches.remove_at(i)
		elif not npc.is_forced_destination():
			# Reached the old spot but the player moved away; retry, then give up.
			if int(entry.get("retries", 0)) > 0:
				entry["retries"] = int(entry.get("retries", 0)) - 1
				entry["remaining"] = maxf(0.5, npc_approach_timeout_sec)
				_issue_approach_destination(npc)
			else:
				_release_approach(entry)
				_pending_approaches.remove_at(i)
		else:
			entry["remaining"] = float(entry.get("remaining", 0.0)) - delta
			if float(entry["remaining"]) <= 0.0:
				npc.clear_forced_destination()
				_release_approach(entry)
				_pending_approaches.remove_at(i)


func _release_approach(entry: Dictionary, preserve_player_lock: bool = false) -> void:
	_release_initiation_party(str(entry.get("initiator_id", "")))
	if not (_dialogue_open and preserve_player_lock):
		_initiation_busy.erase(_player_id())


## Topics that have at least two authored rollable replies. Only these can open
## an NPC-initiated talk; otherwise the 2-3 reply contract silently collapses to
## the generated single-line fallback (review finding 2).
func _topics_with_replies(topics: Array, responses: Array) -> Array:
	var supported: Dictionary = {}
	for item in responses:
		var reply: DialogueResponse = item as DialogueResponse
		if reply == null or reply.is_line_only() or reply.topic_id.is_empty():
			continue
		supported[reply.topic_id] = int(supported.get(reply.topic_id, 0)) + 1
	var result: Array = []
	for item in topics:
		var topic: DialogueTopic = item as DialogueTopic
		if topic == null:
			continue
		if int(supported.get(topic.id, 0)) >= 2:
			result.append(topic)
	return result


## Open the NPC-initiated reply flow with the player as the target. The opening
## topic is spoken only (no roll/deltas); the player's reply is the final change.
func _begin_npc_conversation(initiator: Npc, initiator_id: String) -> void:
	if _dialogue_open or _conversation_ui == null or initiator.instance == null:
		return
	var resources: Dictionary = _dialogue_resources()
	_conversation = Conversation.new()
	_conversation.begin_npc_initiated(
		initiator.instance, _player_instance,
		initiator.instance.resolve_template(), _player_template,
		_next_conversation_seed(initiator_id), TimeManager.get_state_name()
	)
	_topics_for_conversation = resources.get("topics", [])
	_greetings_for_conversation = resources.get("greetings", [])
	_responses_for_conversation = resources.get("responses", [])
	_index_conversation_responses(_responses_for_conversation)
	_conversation_npc_id = initiator_id
	_dialogue_target = null
	_dialogue_open = true
	_lock_conversation_parties(initiator, initiator_id)
	_initiation_cooldowns[initiator_id] = npc_initiation_cooldown_sec

	var opening_topics: Array = _topics_with_replies(
		_topics_for_conversation, _responses_for_conversation
	)
	if opening_topics.is_empty():
		opening_topics = _topics_for_conversation
	var opening: Dictionary = _conversation.choose_opening_topic(opening_topics)
	npc_interaction_started.emit(str(opening.get("id", "")), initiator_id, _player_id())
	_show_line(
		_npc_name(), str(opening.get("text", "")), ["Continue"],
		[{"kind": "replies"}], "You"
	)


## Player position for proximity weighting. The player instance is not mirrored
## every physics tick, so read the live scene node when present.
func _player_position() -> Vector2:
	var player := get_node_or_null("Player") as Node2D
	if player != null:
		return player.global_position
	return _player_instance.position if _player_instance != null else Vector2.ZERO


func _lock_initiation_party(id: String, npc: Npc) -> void:
	_initiation_busy[id] = true
	if npc != null and is_instance_valid(npc):
		# Freeze movement without clearing the goal/nav target; releasing later
		# also applies any class snap that arrived mid-conversation.
		npc.set_conversation_busy(true)


## Tick cooldowns and hold timers. Multiple holds can expire in the same frame;
## each releases only its own two participants.
func _update_initiations(delta: float) -> void:
	for id in _initiation_cooldowns.keys():
		var remaining: float = float(_initiation_cooldowns[id]) - delta
		if remaining <= 0.0:
			_initiation_cooldowns.erase(id)
		else:
			_initiation_cooldowns[id] = remaining

	if _active_initiations.is_empty():
		return
	var expired: Array = []
	for i in range(_active_initiations.size() - 1, -1, -1):
		var entry: Dictionary = _active_initiations[i]
		var hold_left: float = float(entry.get("remaining", 0.0)) - delta
		if hold_left > 0.0:
			entry["remaining"] = hold_left
		else:
			expired.append(entry)
			_active_initiations.remove_at(i)
	for entry in expired:
		_release_initiation_party(str(entry.get("initiator_id", "")))
		_release_initiation_party(str(entry.get("target_id", "")))


func _release_initiation_party(id: String) -> void:
	_initiation_busy.erase(id)
	var npc: Npc = _npcs_by_id.get(id) as Npc
	if npc != null and is_instance_valid(npc):
		npc.set_conversation_busy(false)


## Drop all active holds (e.g. on leaving free time) so no busy flag leaks into
## class or a new day.
func _clear_active_initiations() -> void:
	for entry in _active_initiations:
		_release_initiation_party(str(entry.get("initiator_id", "")))
		_release_initiation_party(str(entry.get("target_id", "")))
	_active_initiations.clear()
	# An approach cannot span a phase boundary. Preserve the player's lock if a
	# conversation is already open, then release it in _close_conversation().
	for entry in _pending_approaches:
		var approaching: Npc = entry.get("npc") as Npc
		if approaching != null and is_instance_valid(approaching):
			approaching.clear_forced_destination()
		_release_approach(entry, true)
	_pending_approaches.clear()
	# A phase change must not silently unlock an open conversation's parties;
	# those flags are released only by _close_conversation().
	for id in _initiation_busy.keys():
		if _dialogue_open and _conversation_locked_ids.has(str(id)):
			continue
		_release_initiation_party(str(id))
	_initiation_elapsed = 0.0


## Connect scene-level listeners before the clock starts.
func _time_connect() -> void:
	if not TimeManager.state_changed.is_connected(_on_state_changed):
		TimeManager.state_changed.connect(_on_state_changed)
	if not TimeManager.skip_simulation_requested.is_connected(_on_skip_requested):
		TimeManager.skip_simulation_requested.connect(_on_skip_requested)
	if not TimeManager.day_started.is_connected(_on_day_started):
		TimeManager.day_started.connect(_on_day_started)


## A new day restarts the seeded initiation stream: the attempt counter must not
## carry over, or replaying day N produces different picks than reaching it in play.
func _on_day_started(_day: int) -> void:
	_initiation_attempts = 0
	_initiation_cooldowns.clear()


## Current player roster id, honouring TimeManager's exported override.
func _player_id() -> String:
	var configured: String = TimeManager.player_character_id
	return configured if not configured.is_empty() else FALLBACK_PLAYER_ID


## True for FREETIME1/2/3. Uses the state argument (ticket-013 review finding 5)
## rather than reading global TimeManager state by name, so a restore or a queued
## signal can never enable AI for the wrong phase.
func _is_free_time_state(state: int) -> bool:
	return TimeManager.is_free_time_state(state)


## Advance NPC-initiation timers every frame, then issue class travel once in the
## final `class_travel_lead_sec` of free time.
func _process(delta: float) -> void:
	_update_initiations(delta)
	_update_approaches(delta)
	if not TimeManager.is_running():
		return
	var state: int = TimeManager.get_state()
	# A skip holds the clock for a short beat while the state is still FREETIME*.
	# That time is explicitly not simulated (ticket 011), so do not initiate in it.
	if (
		npc_initiation_enabled
		and not _dialogue_open
		and not TimeManager.is_skipping()
		and _npc_gate_open()
	):
		_initiation_elapsed += delta
		if _initiation_elapsed >= maxf(0.1, npc_initiation_check_interval_sec):
			_initiation_elapsed = 0.0
			_try_npc_initiations()
	if _class_travel_issued or not _is_free_time_state(state):
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
	if not _is_free_time_state(new_state):
		# Hold timers are cleared on leaving free time; an open conversation keeps
		# its own locks until _close_conversation() (see _clear_active_initiations).
		_clear_active_initiations()
	if _is_free_time_state(new_state):
		sync_ai_state()
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
