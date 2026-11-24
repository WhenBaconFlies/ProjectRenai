extends Node

## ChunkManager
##
## Autoload that owns tiered NPC simulation for ticket 019. It is the single
## owner of three related jobs:
##   1. Tier assignment — player-centered, in chunk units, with hysteresis
##      (promote at the inner radius, demote at the outer radius + buffer).
##   2. Promotion/demotion — promotion interpolates the NPC node from its coarse
##      position to the authoritative instance position over ~0.5 s; demotion is
##      instant and preserves all instance state.
##   3. NPC tick scheduler — close ticks every frame, near every N seconds, far
##      every 5-10 s with the full accumulated dt (coarse straight-line sim).
##
## The manager never owns NPC state: instances stay authoritative and are saved
## normally. `tier` and `NpcInstance.coarse_position` are runtime-only (unexported
## and excluded from snapshots), so loading a save recomputes them from the
## player's position via setup()/refresh_tiers().
##
## Deliberately NPC-simulation-only: the renderer keeps its own chunk radii from
## ticket 020. This autoload is registered with the `*` prefix in project.godot.

## Emitted whenever an NPC crosses a tier boundary (after the new tier is set).
signal tier_changed(npc: Npc, old_tier: String, new_tier: String)

## Emitted each time the scheduler actually runs an NPC step. Observers can count
## ticks by tier without reaching into the accumulator bookkeeping.
signal npc_ticked(npc: Npc, tier: String, dt: float)

## Radii, tick rates and defaults. A fresh ChunkConfig is used when unset.
@export var config: ChunkConfig

## Registered Npc nodes (Array[Npc] kept untyped for headless compatibility).
var _npcs: Array = []

## Node whose global_position drives tier assignment (normally the player).
var _focus: Node2D = null
var _focus_position: Vector2 = Vector2.ZERO

## Optional map for chunk-pixel conversion; a config fallback is used when null.
var _map: Map = null

## instance-id -> accumulated seconds since the NPC's last tick.
var _tick_accum: Dictionary = {}
## instance-id -> { from: Vector2, elapsed: float, duration: float }.
var _promotions: Dictionary = {}
## instance-id -> total simulated ticks (diagnostics).
var _ticks_by_id: Dictionary = {}
## Last tier-boundary events, newest last (diagnostics / thrash checks).
var _tier_changes: Array = []


func _ready() -> void:
	if config == null:
		config = ChunkConfig.new()


## --- Configuration -----------------------------------------------------------

## Swap the tuning config at runtime. Clears scheduling state so a tick-rate
## change takes effect immediately rather than halfway through an accumulator.
func set_config(value: ChunkConfig) -> void:
	config = value if value != null else ChunkConfig.new()
	_tick_accum.clear()
	_promotions.clear()
	_update_tiers()
	# Visibility is applied inside _apply_tier() only when a tier actually
	# changes, so a hide_far_npcs toggle needs its own pass (review finding 2).
	for entry in _npcs:
		var npc: Npc = _valid_npc(entry)
		if npc != null and npc.instance != null:
			npc.visible = not (
				get_config().hide_far_npcs and npc.instance.tier == NpcInstance.TIER_FAR
			)


## Read the active config (always non-null after _ready()).
func get_config() -> ChunkConfig:
	if config == null:
		config = ChunkConfig.new()
	return config


## --- Scene wiring ------------------------------------------------------------

## One-call setup used by Game.gd. Registers every NPC, installs the focus node,
## optionally supplies the map for chunk-pixel math, and computes fresh tiers
## from the focus position (ignoring hysteresis, as on load / fresh start).
func setup(focus_node: Node2D, npcs: Array, map: Map = null) -> void:
	clear()
	_map = map
	set_focus(focus_node)
	for entry in npcs:
		var npc: Npc = _valid_npc(entry)
		if npc != null:
			register_npc(npc)
	refresh_tiers()


## Replace the focus node. Its current global_position becomes the new center.
func set_focus(focus_node: Node2D) -> void:
	_focus = focus_node
	if focus_node != null and is_instance_valid(focus_node):
		_focus_position = focus_node.global_position


## Headless/test seam: center tiers on an explicit world position and recompute
## immediately (no frame wait). Clears any focus node.
func set_focus_position(world: Vector2) -> void:
	_focus = null
	_focus_position = world
	_update_tiers()


## Read the live focus node (if any) and recompute tiers. Called every frame by
## _process(); safe to call manually from tests.
func update_focus() -> void:
	if _focus != null and is_instance_valid(_focus):
		_focus_position = _focus.global_position
	_update_tiers()


## Drop all registrations and restore NPCs to self-driven simulation. Used on
## scene teardown/reload so no stale node references survive.
func clear() -> void:
	for entry in _npcs:
		var npc: Npc = _valid_npc(entry)
		if npc != null and is_instance_valid(npc):
			npc.set_chunk_managed(false)
			npc.visible = true
	_npcs.clear()
	_tick_accum.clear()
	_promotions.clear()
	_ticks_by_id.clear()
	_tier_changes.clear()
	_focus = null
	_map = null


## Attach a map for chunk-pixel conversion. Passing null restores the config
## fallback used by headless tests.
func set_map(map: Map) -> void:
	_map = map


## Register one NPC with the scheduler. Safe for repeated calls (idempotent).
func register_npc(npc: Npc) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	if _npcs.has(npc):
		return
	_npcs.append(npc)
	npc.set_chunk_managed(true)
	var id: String = _id_for(npc)
	_tick_accum[id] = 0.0
	if npc.instance != null:
		npc.instance.coarse_position = npc.instance.position


## Unregister one NPC, restoring its legacy per-frame simulation path.
func unregister_npc(npc: Npc) -> void:
	if npc == null:
		return
	_npcs.erase(npc)
	_promotions.erase(_id_for(npc))
	_tick_accum.erase(_id_for(npc))
	if is_instance_valid(npc):
		npc.set_chunk_managed(false)
		npc.visible = true
		# Without a manager no further tier updates happen, so a stale FAR tier
		# would leave this NPC permanently hidden from interaction (review #5).
		if npc.instance != null:
			npc.instance.tier = NpcInstance.TIER_CLOSE
			npc.instance.coarse_position = npc.instance.position


## Registered NPCs in registration order (copy).
func get_registered_npcs() -> Array:
	return _npcs.duplicate()


## --- Tier assignment ---------------------------------------------------------

## Force a fresh, hysteresis-free tier assignment for every registered NPC.
## This is the load/fresh-start path: no tier state is ever read from a save.
func refresh_tiers() -> void:
	_promotions.clear()
	for entry in _npcs:
		var npc: Npc = _valid_npc(entry)
		if npc == null or not is_instance_valid(npc) or npc.instance == null:
			continue
		var distance: int = _chunk_distance(npc.instance.position)
		_apply_tier(npc, _tier_for(distance, npc.instance.tier, true), true)


## Recompute tiers using hysteresis. Called each frame from update_focus(), and
## also after a teleport (e.g. class hard-snap) when Game calls update_focus().
func _update_tiers() -> void:
	for entry in _npcs:
		var npc: Npc = _valid_npc(entry)
		if npc == null or not is_instance_valid(npc) or npc.instance == null:
			continue
		var distance: int = _chunk_distance(npc.instance.position)
		_apply_tier(npc, _tier_for(distance, npc.instance.tier, false), true)


## Pure tier decision. Ranks: close=0, near=1, far=2. Promotion happens at the
## inner radius; demotion needs the outer radius + the hysteresis buffer.
func _tier_for(distance: int, current: String, direct: bool) -> String:
	var cfg: ChunkConfig = get_config()
	var close_r: int = maxi(0, cfg.close_radius_chunks)
	var near_r: int = maxi(close_r, cfg.near_radius_chunks)
	var buffer: int = maxi(0, cfg.hysteresis_chunks)

	if direct:
		if distance <= close_r:
			return NpcInstance.TIER_CLOSE
		if distance <= near_r:
			return NpcInstance.TIER_NEAR
		return NpcInstance.TIER_FAR

	match current:
		NpcInstance.TIER_CLOSE:
			if distance <= close_r + buffer:
				return NpcInstance.TIER_CLOSE
			if distance <= near_r + buffer:
				return NpcInstance.TIER_NEAR
			return NpcInstance.TIER_FAR
		NpcInstance.TIER_NEAR:
			if distance <= close_r:
				return NpcInstance.TIER_CLOSE
			if distance <= near_r + buffer:
				return NpcInstance.TIER_NEAR
			return NpcInstance.TIER_FAR
		_:  # far
			if distance <= close_r:
				return NpcInstance.TIER_CLOSE
			if distance <= near_r:
				return NpcInstance.TIER_NEAR
			return NpcInstance.TIER_FAR


## Apply a tier change: begin/stop promotion interpolation, hide/show the node,
## re-aim the nav agent on promotion, and emit tier_changed.
func _apply_tier(npc: Npc, new_tier: String, animate: bool) -> void:
	if npc == null or not is_instance_valid(npc) or npc.instance == null:
		return
	var instance: NpcInstance = npc.instance
	var old_tier: String = instance.tier
	if old_tier == new_tier:
		return

	var id: String = _id_for(npc)
	var promoting: bool = _tier_rank(new_tier) < _tier_rank(old_tier)
	if promoting:
		# Only interpolate when there is an actual visual gap. In normal play the
		# fine/coarse step already mirrors global_position into instance.position,
		# so a gapless promotion must not freeze simulation for the full 0.5 s
		# (review finding 1).
		var gap: float = npc.global_position.distance_to(instance.position)
		instance.coarse_position = npc.global_position
		npc.visible = true
		if animate and gap > 0.01 and get_config().promotion_duration_sec > 0.0:
			_promotions[id] = {
				"from": npc.global_position,
				"elapsed": 0.0,
				"duration": maxf(0.01, get_config().promotion_duration_sec),
			}
		# The authoritative position may have been snapped while the NPC was far;
		# re-aim the navigation agent so fine simulation resumes toward the goal.
		npc.reconcile_after_promotion()
	else:
		_promotions.erase(id)
		instance.coarse_position = instance.position
		if get_config().hide_far_npcs and new_tier == NpcInstance.TIER_FAR:
			npc.visible = false

	instance.tier = new_tier
	_tick_accum[id] = 0.0
	_tier_changes.append({
		"id": id, "old": old_tier, "new": new_tier,
	})
	tier_changed.emit(npc, old_tier, new_tier)


## --- Interaction guard -------------------------------------------------------

## True only in the steady state: far/near NPCs are not interactable until the
## player explicitly tries (which promotes them via promote_for_interaction()).
func is_interactable(npc: Npc) -> bool:
	return (
		npc != null and is_instance_valid(npc)
		and npc.instance != null and npc.instance.tier == NpcInstance.TIER_CLOSE
	)


## Force-promote a non-close NPC to close so an explicit interaction attempt
## never dead-ends. Returns false for an invalid NPC; otherwise true (including
## the no-op case where the NPC was already close).
func promote_for_interaction(npc: Npc) -> bool:
	if npc == null or not is_instance_valid(npc) or npc.instance == null:
		return false
	if npc.instance.tier != NpcInstance.TIER_CLOSE:
		_apply_tier(npc, NpcInstance.TIER_CLOSE, true)
	return true


## Current tier of `npc`, or an empty string for an invalid/unregistered node.
func get_tier(npc: Npc) -> String:
	if npc == null or not is_instance_valid(npc) or npc.instance == null:
		return ""
	return npc.instance.tier


## Counts by tier across registered NPCs (diagnostics / assertions).
func get_tier_counts() -> Dictionary:
	var result: Dictionary = {
		NpcInstance.TIER_CLOSE: 0,
		NpcInstance.TIER_NEAR: 0,
		NpcInstance.TIER_FAR: 0,
	}
	for entry in _npcs:
		var npc: Npc = _valid_npc(entry)
		if npc != null and is_instance_valid(npc) and npc.instance != null:
			result[npc.instance.tier] = int(result.get(npc.instance.tier, 0)) + 1
	return result


## Tier-boundary events (deep copy). Used to prove hysteresis stops thrash.
func get_tier_changes() -> Array:
	return _tier_changes.duplicate(true)


## Number of simulated ticks for one instance id.
func get_tick_count(instance_id: String) -> int:
	return int(_ticks_by_id.get(instance_id, 0))


## --- Tick scheduler ----------------------------------------------------------

func _process(delta: float) -> void:
	update_focus()
	tick_npcs(delta)


## Advance every registered NPC's scheduler by `delta`. Close NPCs are stepped
## every call with `delta`; near/far NPCs accumulate and step with the full
## elapsed dt when their interval is reached. Far steps use coarse simulation.
func tick_npcs(delta: float) -> void:
	if delta <= 0.0:
		return
	_advance_promotions(delta)
	for entry in _npcs:
		var npc: Npc = _valid_npc(entry)
		if npc == null or not is_instance_valid(npc) or npc.instance == null:
			continue
		var id: String = _id_for(npc)
		# A promoting NPC is moving toward its authoritative position; simulating
		# it in parallel would fight the interpolation for the same 0.5 s.
		if _promotions.has(id):
			continue

		var tier: String = npc.instance.tier
		var interval: float = _tick_interval(tier)
		var accum: float = float(_tick_accum.get(id, 0.0)) + delta
		if interval > 0.0 and accum < interval:
			_tick_accum[id] = accum
			continue
		var step_dt: float = accum if interval > 0.0 else delta
		_tick_accum[id] = 0.0
		npc.simulate_tick(step_dt, tier == NpcInstance.TIER_FAR)
		_ticks_by_id[id] = int(_ticks_by_id.get(id, 0)) + 1
		npc_ticked.emit(npc, tier, step_dt)


## Seconds between ticks for a tier (0 = every frame).
func _tick_interval(tier: String) -> float:
	var cfg: ChunkConfig = get_config()
	match tier:
		NpcInstance.TIER_CLOSE:
			return maxf(0.0, cfg.close_tick_sec)
		NpcInstance.TIER_NEAR:
			return maxf(0.0, cfg.near_tick_sec)
		_:
			return maxf(0.0, cfg.far_tick_sec)


## Move promoting NPC nodes from their captured coarse position toward the
## authoritative instance position. Completion snaps exactly onto the target.
func _advance_promotions(delta: float) -> void:
	for id in _promotions.keys():
		var data: Dictionary = _promotions[id]
		var npc: Npc = _npc_by_id(id)
		if npc == null or npc.instance == null:
			_promotions.erase(id)
			continue
		data["elapsed"] = float(data.get("elapsed", 0.0)) + delta
		var t: float = clampf(
			float(data.get("elapsed", 0.0)) / maxf(0.01, float(data.get("duration", 0.5))),
			0.0, 1.0
		)
		var from: Vector2 = data.get("from", Vector2.ZERO)
		npc.global_position = from.lerp(npc.instance.position, t)
		if t >= 1.0:
			npc.global_position = npc.instance.position
			_promotions.erase(id)


## True while `id` has an in-flight promotion interpolation.
func is_promoting(instance_id: String) -> bool:
	return _promotions.has(instance_id)


## --- Geometry helpers --------------------------------------------------------

## Chebyshev chunk distance between the focus and `point`.
func _chunk_distance(point: Vector2) -> int:
	var a: Vector2i = _chunk_of(_focus_position)
	var b: Vector2i = _chunk_of(point)
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Chunk containing `point`. Uses the attached Map when available; otherwise the
## config fallback pixel size keeps headless tests deterministic.
func _chunk_of(point: Vector2) -> Vector2i:
	if _map != null and _map.chunk_pixel_size() > 0:
		return _map.world_to_chunk(point)
	var size: int = maxi(1, get_config().fallback_chunk_pixel_size)
	return Vector2i(floori(point.x / float(size)), floori(point.y / float(size)))


## --- Small utilities ---------------------------------------------------------

func _tier_rank(tier: String) -> int:
	match tier:
		NpcInstance.TIER_CLOSE:
			return 0
		NpcInstance.TIER_NEAR:
			return 1
		_:
			return 2


## Safe cast for an array entry that may reference a node freed by a scene
## change. Casting a freed object with `as` itself logs an error in Godot 4.2,
## so validity is checked before the cast.
func _valid_npc(entry: Variant) -> Npc:
	if entry == null or not (entry is Object) or not is_instance_valid(entry):
		return null
	return entry as Npc


## Stable dictionary key for an NPC (instance id when available, object id else).
func _id_for(npc: Npc) -> String:
	if npc != null and npc.instance != null and not npc.instance.instance_id.is_empty():
		return npc.instance.instance_id
	return str(npc.get_instance_id()) if npc != null else "<null>"


func _npc_by_id(id: String) -> Npc:
	for entry in _npcs:
		var npc: Npc = _valid_npc(entry)
		if npc == null or not is_instance_valid(npc):
			continue
		if _id_for(npc) == id:
			return npc
	return null
