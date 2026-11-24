## ChunkManagerTest
##
## Persistent headless harness for ticket 019 (ChunkManager + tiered NPC
## simulation). It is attached to /root by ChunkManagerBootstrap so it survives
## the scene change into the real Game.tscn. Synthetic NPCs with a deterministic
## config (100 px per chunk) exercise tier assignment, hysteresis, promotion
## interpolation, tick rates, coarse simulation and the interaction guard; the
## real Game.tscn then proves autoload wiring, load-time recompute and that the
## shipped 1x1-chunk debug map keeps every NPC in the close tier.
##
## Prints ALL_019_CHECKS_PASSED only when every check passes.
extends Node


const TEST_CONFIG: Dictionary = {
	"close_radius_chunks": 2,
	"near_radius_chunks": 4,
	"hysteresis_chunks": 1,
	"promotion_duration_sec": 0.5,
	"close_tick_sec": 0.0,
	"near_tick_sec": 0.25,
	"far_tick_sec": 5.0,
	"fallback_chunk_pixel_size": 100,
	"hide_far_npcs": true,
}

var _passed: int = 0
var _failed: int = 0

var _original_config: ChunkConfig = null
var _synthetic_root: Node2D = null
var _npcs: Dictionary = {}

var _tier_changes_by_id: Dictionary = {}
var _tick_counts: Dictionary = {}
var _last_tick_dt: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	ChunkManager.set_process(false)  # deterministic manual ticking
	_check_chunks_1()
	_check_npc_instance_fields()
	_setup_synthetic()
	_check_tier_assignment()
	_check_hysteresis()
	_check_promotion_interpolation()
	_check_gapless_promotion()
	_check_config_visibility()
	_check_demotion_instant()
	_check_tick_rates()
	_check_coarse_simulation()
	_check_interaction_guard()
	_check_no_thrash()
	_check_unregister_consistency()
	_cleanup_synthetic()
	await _check_real_game()
	_finish()


## --- Checkbox 1: autoload + config -------------------------------------------

func _check_chunks_1() -> void:
	_check(ChunkManager != null, "1: ChunkManager autoload exists")
	_check(
		str(ProjectSettings.get_setting("autoload/ChunkManager", "")).contains("ChunkManager.gd"),
		"1: ChunkManager registered as an autoload in project.godot"
	)
	var defaults := ChunkConfig.new()
	_check(
		defaults.close_radius_chunks == 2 and defaults.near_radius_chunks == 4
		and defaults.far_tick_sec == 5.0 and defaults.promotion_duration_sec == 0.5,
		"7: ChunkConfig exposes sensible defaults (close 2, near 4, far 5s, promote 0.5s)"
	)
	_check(
		defaults.to_dictionary().has("near_tick_sec") and defaults.to_dictionary().has("fallback_chunk_pixel_size"),
		"7: config dictionary exposes tick rates and radius knobs"
	)


## --- Checkbox 6: runtime-only NpcInstance fields -----------------------------

func _check_npc_instance_fields() -> void:
	var instance := NpcInstance.new()
	instance.instance_id = "test:fields"
	instance.template_id = "char:sam"
	_check(
		"tier" in instance and "coarse_position" in instance,
		"6: NpcInstance carries tier and coarse_position"
	)
	instance.tier = NpcInstance.TIER_FAR
	instance.coarse_position = Vector2(12, 34)
	var snapshot: Dictionary = instance.snapshot()
	_check(
		not snapshot.has("tier") and not snapshot.has("coarse_position"),
		"6: tier and coarse_position are excluded from snapshot()"
	)
	var restored: NpcInstance = NpcInstance.from_snapshot(snapshot)
	_check(
		restored != null and restored.tier == NpcInstance.TIER_CLOSE
		and restored.coarse_position == Vector2.ZERO,
		"18: load path rebuilds with default tier/coarse (recomputed, not persisted)"
	)


## --- Synthetic fixtures ------------------------------------------------------

func _setup_synthetic() -> void:
	_original_config = ChunkManager.get_config()
	var cfg := ChunkConfig.new()
	for key in TEST_CONFIG.keys():
		cfg.set(key, TEST_CONFIG[key])
	ChunkManager.set_config(cfg)
	ChunkManager.clear()
	if not ChunkManager.tier_changed.is_connected(_on_tier_changed):
		ChunkManager.tier_changed.connect(_on_tier_changed)
	if not ChunkManager.npc_ticked.is_connected(_on_npc_ticked):
		ChunkManager.npc_ticked.connect(_on_npc_ticked)

	_synthetic_root = Node2D.new()
	_synthetic_root.name = "SyntheticNpcs"
	add_child(_synthetic_root)

	_make_synthetic("test:close", Vector2(150, 0))
	_make_synthetic("test:near", Vector2(350, 0))
	_make_synthetic("test:far", Vector2(650, 0))
	ChunkManager.set_focus_position(Vector2.ZERO)
	ChunkManager.refresh_tiers()


func _make_synthetic(id: String, position: Vector2) -> Npc:
	var instance := NpcInstance.new()
	instance.instance_id = id
	instance.template_id = "char:sam"
	instance.position = position
	instance.coarse_position = position
	instance.stats = {"charisma": 10}
	instance.meters = {"test:other": {"familiarity": 42, "affection": 7}}

	var npc := Npc.new()
	npc.name = "Npc_%s" % id.replace(":", "_")
	_synthetic_root.add_child(npc)
	npc.setup(instance)
	ChunkManager.register_npc(npc)
	_npcs[id] = npc
	return npc


func _cleanup_synthetic() -> void:
	if ChunkManager.tier_changed.is_connected(_on_tier_changed):
		ChunkManager.tier_changed.disconnect(_on_tier_changed)
	if ChunkManager.npc_ticked.is_connected(_on_npc_ticked):
		ChunkManager.npc_ticked.disconnect(_on_npc_ticked)
	ChunkManager.clear()
	if _synthetic_root != null and is_instance_valid(_synthetic_root):
		_synthetic_root.queue_free()
	_synthetic_root = null
	_npcs.clear()
	ChunkManager.set_config(_original_config)


## --- Checkboxes 1, 18: tier assignment --------------------------------------

func _check_tier_assignment() -> void:
	_check(ChunkManager.get_tier(_npcs["test:close"]) == NpcInstance.TIER_CLOSE,
		"1: NPC at chunk distance 1 is close")
	_check(ChunkManager.get_tier(_npcs["test:near"]) == NpcInstance.TIER_NEAR,
		"1: NPC at chunk distance 3 is near")
	_check(ChunkManager.get_tier(_npcs["test:far"]) == NpcInstance.TIER_FAR,
		"1: NPC at chunk distance 6 is far")
	var counts: Dictionary = ChunkManager.get_tier_counts()
	_check(
		counts.get(NpcInstance.TIER_CLOSE, 0) == 1
		and counts.get(NpcInstance.TIER_NEAR, 0) == 1
		and counts.get(NpcInstance.TIER_FAR, 0) == 1,
		"1: tier counts reflect all three tiers (got %s)" % str(counts)
	)


## --- Checkbox 2: hysteresis --------------------------------------------------

func _check_hysteresis() -> void:
	var near_npc: Npc = _npcs["test:near"]  # stays at x=350 (chunk 3)
	# Near -> close at the inner radius (distance 2).
	ChunkManager.set_focus_position(Vector2(100, 0))
	_check(ChunkManager.get_tier(near_npc) == NpcInstance.TIER_CLOSE,
		"2: promote to close at inner radius (distance 2)")
	# Close persists one chunk past that radius (demote threshold = 3, not 2).
	ChunkManager.set_focus_position(Vector2.ZERO)
	_check(ChunkManager.get_tier(near_npc) == NpcInstance.TIER_CLOSE,
		"2: close persists inside the +1 buffer (distance 3)")
	# Demote to near beyond the buffer.
	ChunkManager.set_focus_position(Vector2(-100, 0))
	_check(ChunkManager.get_tier(near_npc) == NpcInstance.TIER_NEAR,
		"2: demote to near beyond close radius + buffer (distance 4)")
	# Near persists through distance 5 (outer radius 4 + buffer 1).
	ChunkManager.set_focus_position(Vector2(-200, 0))
	_check(ChunkManager.get_tier(near_npc) == NpcInstance.TIER_NEAR,
		"2: near persists inside the outer +1 buffer (distance 5)")
	# Far beyond that.
	ChunkManager.set_focus_position(Vector2(-300, 0))
	_check(ChunkManager.get_tier(near_npc) == NpcInstance.TIER_FAR,
		"2: demote to far beyond near radius + buffer (distance 6)")
	# Promote from far at the inner near radius.
	ChunkManager.set_focus_position(Vector2.ZERO)
	_check(ChunkManager.get_tier(near_npc) == NpcInstance.TIER_NEAR,
		"2: promote far -> near at inner radius (distance 3)")
	ChunkManager.set_focus_position(Vector2(100, 0))
	_check(ChunkManager.get_tier(near_npc) == NpcInstance.TIER_CLOSE,
		"2: promote near -> close at inner radius (distance 2)")


## --- Checkbox 3: promotion interpolation ------------------------------------

func _check_promotion_interpolation() -> void:
	var far_npc: Npc = _npcs["test:far"]
	far_npc.instance.position = Vector2(150, 0)  # authoritative snap while far
	far_npc.global_position = Vector2(650, 0)  # visual node still at coarse spot
	ChunkManager.set_focus_position(Vector2.ZERO)
	_check(ChunkManager.get_tier(far_npc) == NpcInstance.TIER_CLOSE,
		"3: far NPC promoted to close on approach")
	_check(ChunkManager.is_promoting(far_npc.instance.instance_id),
		"3: promotion starts a position interpolation")
	ChunkManager.tick_npcs(0.25)
	var mid_x: float = far_npc.global_position.x
	_check(mid_x > 150.0 and mid_x < 650.0,
		"3: position interpolates at half duration (x=%.1f)" % mid_x)
	ChunkManager.tick_npcs(0.25)
	_check(far_npc.global_position.distance_to(Vector2(150, 0)) < 0.01,
		"3: position reaches authoritative target after ~0.5s")
	_check(not ChunkManager.is_promoting(far_npc.instance.instance_id),
		"3: interpolation ends after the configured duration")


## --- Review finding 1: no gap means no freeze --------------------------------

func _check_gapless_promotion() -> void:
	_reset_synthetic_state()
	var near_npc: Npc = _npcs["test:near"]
	var id: String = near_npc.instance.instance_id
	ChunkManager.set_focus_position(Vector2(100, 0))  # chunk distance 2 -> close
	_check(ChunkManager.get_tier(near_npc) == NpcInstance.TIER_CLOSE,
		"1: gapless promotion reaches close tier")
	_check(not ChunkManager.is_promoting(id),
		"1: promotion with no visual gap does not start interpolation")
	var before: int = ChunkManager.get_tick_count(id)
	ChunkManager.tick_npcs(0.05)
	_check(ChunkManager.get_tick_count(id) > before,
		"1: NPC keeps simulating immediately after a gapless promotion")


## --- Review finding 2: config visibility pass --------------------------------

func _check_config_visibility() -> void:
	_reset_synthetic_state()
	var far_npc: Npc = _npcs["test:far"]
	_check(not far_npc.visible, "7: far NPC hidden by default config")
	var cfg: ChunkConfig = ChunkManager.get_config()
	cfg.hide_far_npcs = false
	ChunkManager.set_config(cfg)
	_check(far_npc.visible, "7: set_config() re-applies hide_far_npcs=false")
	cfg.hide_far_npcs = true
	ChunkManager.set_config(cfg)
	_check(not far_npc.visible, "7: set_config() re-applies hide_far_npcs=true")


## --- Checkbox 3/14/18: demotion is instant, state preserved ------------------

func _check_demotion_instant() -> void:
	var close_npc: Npc = _npcs["test:close"]
	var before_state: Dictionary = close_npc.instance.stats.duplicate(true)
	ChunkManager.set_focus_position(Vector2(900, 0))
	_check(ChunkManager.get_tier(close_npc) == NpcInstance.TIER_FAR,
		"15: demotion to far is immediate on leaving the radius")
	_check(not ChunkManager.is_promoting(close_npc.instance.instance_id),
		"3: demotion has no interpolation (instant)")
	_check(close_npc.instance.coarse_position == close_npc.instance.position,
		"14: coarse position mirrors authoritative position on demotion")
	_check(close_npc.instance.stats == before_state,
		"14: demotion preserves NPC identity/state")


## --- Checkbox 4: tier-appropriate tick rates --------------------------------

func _check_tick_rates() -> void:
	_reset_synthetic_state()
	for id in _tick_counts.keys():
		_tick_counts[id] = 0
		_last_tick_dt[id] = 0.0
	for _i in range(20):
		ChunkManager.tick_npcs(0.05)  # 1.0 s total
	_check(int(_tick_counts.get(NpcInstance.TIER_CLOSE, 0)) == 20,
		"4: close tier ticks every frame (got %d)" % int(_tick_counts.get(NpcInstance.TIER_CLOSE, 0)))
	var near_ticks: int = int(_tick_counts.get(NpcInstance.TIER_NEAR, 0))
	_check(near_ticks >= 3 and near_ticks <= 5,
		"4: near tier ticks at ~0.25s intervals (got %d in 1s)" % near_ticks)
	_check(int(_tick_counts.get(NpcInstance.TIER_FAR, 0)) == 0,
		"4: far tier does not tick before its 5s interval")
	ChunkManager.tick_npcs(5.0)
	_check(int(_tick_counts.get(NpcInstance.TIER_FAR, 0)) == 1,
		"4: far tier ticks once after the full interval")
	_check(float(_last_tick_dt.get(NpcInstance.TIER_FAR, 0.0)) >= 5.0,
		"4: far tick receives the large accumulated dt (got %.2f)" % float(_last_tick_dt.get(NpcInstance.TIER_FAR, 0.0)))


## --- Checkbox 5: far NPCs keep state and use coarse pathfinding -------------

func _check_coarse_simulation() -> void:
	var far_npc: Npc = _npcs["test:far"]
	var instance: NpcInstance = far_npc.instance
	ChunkManager.set_focus_position(Vector2.ZERO)
	ChunkManager.refresh_tiers()
	instance.position = Vector2(650, 0)
	instance.coarse_position = Vector2(650, 0)
	instance.current_goal = "test:coarse"
	instance.goal_destination = Vector2(650, 300)
	far_npc.global_position = Vector2(650, 0)
	var map := Map.new()  # preserves the set_ai_enabled seam without a baked navmesh
	far_npc.set_ai_enabled(true, map, 0, true)
	var stats_before: Dictionary = instance.stats.duplicate(true)
	var meters_before: Dictionary = instance.meters.duplicate(true)
	ChunkManager.tick_npcs(5.0)
	_check(instance.position.y > 0.0 and absf(instance.position.x - 650.0) < 0.01,
		"5: far NPC advances straight toward its goal (x=%.1f y=%.1f)" % [
			instance.position.x, instance.position.y
		])
	_check(instance.coarse_position == instance.position,
		"5: coarse position tracks the simulated far position")
	_check(far_npc.global_position.distance_to(instance.coarse_position) < 0.01,
		"5: far node renders at the coarse position")
	_check(instance.stats == stats_before and instance.meters == meters_before,
		"5: identity/state (stats, meters) unchanged by coarse simulation")
	# Two more large ticks land on the goal and then run the arrival path.
	ChunkManager.tick_npcs(5.0)
	ChunkManager.tick_npcs(5.0)
	_check(instance.coarse_position == instance.position,
		"4: coarse position mirrors authoritative position on far arrival")


## --- Checkboxes 8, 9: interaction guard -------------------------------------

func _check_interaction_guard() -> void:
	_reset_synthetic_state()
	var close_npc: Npc = _npcs["test:close"]
	var near_npc: Npc = _npcs["test:near"]
	var far_npc: Npc = _npcs["test:far"]
	_check(ChunkManager.is_interactable(close_npc), "9: close NPC is interactable")
	_check(not ChunkManager.is_interactable(near_npc), "9: near NPC is not interactable in steady state")
	_check(not ChunkManager.is_interactable(far_npc), "9: far NPC is not interactable in steady state")
	_check(ChunkManager.promote_for_interaction(near_npc), "8: near interaction attempt promotes")
	_check(near_npc.instance.tier == NpcInstance.TIER_CLOSE, "8: promoted near NPC becomes close")
	_check(ChunkManager.promote_for_interaction(far_npc), "8: far interaction attempt promotes")
	_check(far_npc.instance.tier == NpcInstance.TIER_CLOSE, "8: promoted far NPC becomes close")


## --- Checkbox 11: no boundary thrash ----------------------------------------

func _check_no_thrash() -> void:
	var npc: Npc = _npcs["test:near"]
	ChunkManager.set_focus_position(Vector2(100, 0))
	ChunkManager.refresh_tiers()  # direct close assignment; may emit one change
	var changes_before: int = _changes_for(npc.instance.instance_id)
	for _i in range(15):
		ChunkManager.set_focus_position(Vector2(100, 0))  # distance 2 -> close
		ChunkManager.set_focus_position(Vector2.ZERO)  # distance 3 -> still close (buffer)
	_check(_changes_for(npc.instance.instance_id) == changes_before,
		"11: oscillating inside the hysteresis band causes no tier changes")


## --- Review finding 5: unregister consistency --------------------------------

func _check_unregister_consistency() -> void:
	_reset_synthetic_state()
	var far_npc: Npc = _npcs["test:far"]
	ChunkManager.unregister_npc(far_npc)
	_check(
		far_npc.instance.tier == NpcInstance.TIER_CLOSE and far_npc.visible,
		"14: unregistering a far NPC restores consistent close/visible state"
	)
	ChunkManager.register_npc(far_npc)


## --- Real scene wiring -------------------------------------------------------

func _check_real_game() -> void:
	GameManager.change_scene("res://scenes/DebugStart.tscn")
	var game: Node = null
	for _i in range(30):
		await get_tree().process_frame
		game = get_tree().root.get_node_or_null("Game")
		if game != null:
			break
	_check(game != null, "10: real Game.tscn loads through DebugStart")
	if game == null:
		return

	var registered: Array = ChunkManager.get_registered_npcs()
	_check(registered.size() == 4, "10: Game registers four NPCs with ChunkManager (got %d)" % registered.size())
	var all_managed: bool = true
	var all_close: bool = true
	for entry in registered:
		var npc: Npc = entry as Npc
		if npc == null:
			continue
		if not npc.chunk_managed:
			all_managed = false
		if not ChunkManager.is_interactable(npc):
			all_close = false
	_check(all_managed, "10: registered NPCs are scheduler-managed")
	_check(all_close, "18: shipped 1x1-chunk map keeps every NPC close")

	var npcs_root: Node = game.get_node_or_null("Npcs")
	var pool_ui: Node = game.get_node_or_null("DialogueLayer/ConversationUI")
	if npcs_root == null or npcs_root.get_child_count() == 0 or pool_ui == null:
		_check(false, "8: real interaction guard (missing scene nodes)")
		return
	var target: Npc = npcs_root.get_child(0) as Npc
	# Review finding 3: a character already claimed by an NPC-initiated hold is
	# rejected before promotion mutates its tier/visibility/nav state.
	var busy: Dictionary = game.get("_initiation_busy")
	busy[target.instance.instance_id] = true
	target.instance.tier = NpcInstance.TIER_NEAR
	game.call("_on_interaction_requested", target)
	_check(target.instance.tier == NpcInstance.TIER_NEAR,
		"8: busy NPC is rejected before any tier promotion")
	busy.erase(target.instance.instance_id)

	target.instance.tier = NpcInstance.TIER_NEAR  # simulate a stale tier
	game.call("_on_interaction_requested", target)
	for _i in range(3):
		await get_tree().process_frame
	_check(target.instance.tier == NpcInstance.TIER_CLOSE,
		"8: real interaction attempt promotes a near NPC to close")
	_check(bool(pool_ui.call("is_open")), "8: promoted NPC can be interacted with")
	game.call("_on_conversation_cancelled")

	# Load-time recompute: a saved instance carries no tier; the live tier must be
	# rebuilt from the player's position rather than restored from the save.
	target.instance.tier = NpcInstance.TIER_FAR
	ChunkManager.refresh_tiers()
	_check(ChunkManager.is_interactable(target),
		"18: refresh_tiers() recomputes tiers from the player position on load")


## --- Helpers -----------------------------------------------------------------

## Put every synthetic NPC back at its canonical chunk distance with a fresh
## direct tier assignment, so later sections do not inherit earlier promotions
## or demotions.
func _reset_synthetic_state() -> void:
	var positions: Dictionary = {
		"test:close": Vector2(150, 0),
		"test:near": Vector2(350, 0),
		"test:far": Vector2(650, 0),
	}
	for id in positions.keys():
		var npc: Npc = _npcs[id]
		var position: Vector2 = positions[id]
		npc.instance.position = position
		npc.instance.coarse_position = position
		npc.instance.current_goal = ""
		npc.instance.goal_destination = Vector2.ZERO
		npc.global_position = position
	ChunkManager.set_focus_position(Vector2.ZERO)
	ChunkManager.refresh_tiers()


func _on_tier_changed(npc: Npc, _old_tier: String, new_tier: String) -> void:
	if npc == null or npc.instance == null:
		return
	var id: String = npc.instance.instance_id
	_tier_changes_by_id[id] = int(_tier_changes_by_id.get(id, 0)) + 1


func _on_npc_ticked(_npc: Npc, tier: String, dt: float) -> void:
	_tick_counts[tier] = int(_tick_counts.get(tier, 0)) + 1
	_last_tick_dt[tier] = dt


func _changes_for(id: String) -> int:
	return int(_tier_changes_by_id.get(id, 0))


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("[019] FAIL: %s" % label)


func _finish() -> void:
	ChunkManager.set_process(true)
	print("[019] checks: %d passed, %d failed" % [_passed, _failed])
	if _failed == 0:
		print("ALL_019_CHECKS_PASSED")
	else:
		print("[019] FAIL: %d check(s) failed" % _failed)
	get_tree().quit()
