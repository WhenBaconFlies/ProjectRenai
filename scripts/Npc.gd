class_name Npc
extends CharacterBody2D

## Npc
##
## Scene-side representation of one NpcInstance. The instance resource owns the
## authoritative data (position, schedule, meters, goal); this node draws a
## generated placeholder body and mirrors position changes into the instance.
## It is a CharacterBody2D with a circular collider and a child NavigationAgent2D
## so it can run ticket 013's goal-driven free-time movement.
##
## Movement is active ONLY while Game.gd enables AI for a FREETIME* state. On
## class entry Game.gd disables AI and applies ticket 012's instant reposition to
## the scheduled classroom marker.

## Group tag used by interaction/dialogue systems to find NPCs.
const GROUP_NAME := "npc"

## Deterministic palette so npcs are visually distinct without art assets.
const PALETTE: Array = [
	Color(0.35, 0.65, 0.90),
	Color(0.90, 0.45, 0.45),
	Color(0.50, 0.80, 0.45),
	Color(0.85, 0.70, 0.35),
	Color(0.70, 0.45, 0.85),
]

## Fill colour of the generated placeholder body.
@export var body_color: Color = Color(0.35, 0.65, 0.90)

## Radius of the drawn body and physics collider.
@export var body_radius: float = 5.0

## Free-time movement speed (pixels/second).
@export var move_speed: float = 40.0

## How quickly velocity approaches the desired direction (pixels/second²).
@export var move_acceleration: float = 240.0

## Seconds without progress before trying a straight-line fallback.
@export var stuck_timeout_sec: float = 1.5

## Seconds of straight-line fallback before re-evaluating the goal.
@export var fallback_timeout_sec: float = 2.5

## Hard upper bound for a forced destination (class travel). Progress-based
## stall detection can miss an oscillating path, so this guarantees the NPC is
## snapped onto its marker well before the end-of-class attendance check. 14 s
## covers the longest classroom↔hangout walk on the large debug map (~9 s).
@export var travel_timeout_sec: float = 14.0

## Short pause at a destination before choosing the next goal.
@export var arrival_pause_sec: float = 0.5

## How far to slide along an obstacle when a physics collision blocks movement.
## The authored v1 navmesh polygons do not fully exclude furniture colliders, so
## local sliding keeps NPCs from getting pinned against desks/benches.
@export var avoidance_distance: float = 24.0
## Seconds to keep sliding along an obstacle before resuming the nav path.
@export var avoidance_duration_sec: float = 0.8

## The runtime instance this node represents. Set once via setup().
var instance: NpcInstance = null

## Pathfinding agent (created in setup() if the scene has no authored one).
var navigation_agent: NavigationAgent2D = null

var _ai_enabled: bool = false
var _map: Map = null
var _seed_value: int = 0
var _eval_count: int = 0

var _stuck_elapsed: float = 0.0
var _fallback_elapsed: float = 0.0
var _arrival_pause: float = 0.0
var _last_position: Vector2 = Vector2.ZERO
var _using_fallback: bool = false
## Set when a no-progress window elapses. Unlike `_using_fallback` (which is
## recomputed from path availability every frame), this persists until the goal
## is re-evaluated, so stuck recovery cannot be erased by a "usable" nav path.
var _force_fallback: bool = false

## True while moving to an externally imposed destination (e.g. class travel)
## rather than a goal chosen by NpcAi. On arrival the body snaps exactly onto
## the destination instead of stopping short at the agent's desired distance.
var _forced_destination: bool = false
## Remaining seconds before a forced destination is snapped regardless of path.
var _travel_timeout: float = -1.0

var _avoid_elapsed: float = 0.0
var _avoid_point: Vector2 = Vector2.ZERO

## True when the ChunkManager autoload owns this NPC's simulation ticks. While
## set, _physics_process() does not simulate; ChunkManager calls simulate_tick()
## at the rate appropriate to this NPC's tier. Unmanaged NPCs (e.g. headless
## helpers constructed directly) keep the legacy per-frame path.
var chunk_managed: bool = false

## True while this NPC is the target of an open conversation (ticket 014).
## Movement freezes for the duration, but the active goal and navigation target
## are deliberately preserved so the NPC resumes where it left off. Ticket 016
## uses `is_busy()` / `is_conversation_busy()` as its "already talking" gate.
var _conversation_busy: bool = false

## Class transition hard-snap requested while talking. A frozen NPC must not be
## teleported out of the conversation; the snap is applied when it is released.
var _pending_move_to: Vector2 = Vector2.ZERO
var _has_pending_move: bool = false


## Bind an instance, place the node at its saved/current position, and ensure a
## collider and navigation agent exist. Safe to call before the node enters the
## scene tree (the spawner calls it right after add_child()).
func setup(p_instance: NpcInstance) -> void:
	instance = p_instance
	add_to_group(GROUP_NAME)
	if instance != null:
		global_position = instance.position
		body_color = _color_for(instance.instance_id)
	_ensure_collider()
	_ensure_navigation_agent()
	resume_saved_goal()
	queue_redraw()


## Instantly move to a world-space position and keep the instance authoritative
## position in sync. Used as the hard-snap fallback on skipped transitions.
func move_to(p_position: Vector2) -> void:
	if _conversation_busy:
		_pending_move_to = p_position
		_has_pending_move = true
		return
	global_position = p_position
	if instance != null:
		instance.position = p_position
	_last_position = p_position
	_ai_enabled = false
	_forced_destination = false
	_force_fallback = false
	_travel_timeout = -1.0
	velocity = Vector2.ZERO


## Enable or disable free-time AI. Disabling clears the active goal, stops
## movement and cancels any forced travel (used for BREAK / class fallback).
## `preserve_goal` is the ticket-017 restore path: resume the serialized goal and
## destination verbatim instead of rolling a fresh one on load.
func set_ai_enabled(
	enabled: bool, map: Map = null, seed_value: int = 0, preserve_goal: bool = false
) -> void:
	_ai_enabled = enabled
	_map = map
	_seed_value = seed_value
	_stuck_elapsed = 0.0
	_fallback_elapsed = 0.0
	_arrival_pause = 0.0
	_using_fallback = false
	_force_fallback = false
	_avoid_elapsed = 0.0
	velocity = Vector2.ZERO
	if not enabled:
		_forced_destination = false
		_travel_timeout = -1.0
		if instance != null:
			instance.current_goal = ""
			instance.goal_destination = Vector2.ZERO
		return

	if preserve_goal and instance != null and not instance.current_goal.is_empty():
		# Saved in-flight goal: do NOT call evaluate_goal() (it would re-roll) and
		# do NOT clear forced class travel (it was restored by resume_saved_goal).
		_forced_destination = instance.current_goal.begins_with("class:")
		_travel_timeout = maxf(0.0, travel_timeout_sec) if _forced_destination else -1.0
		_last_position = global_position
		if navigation_agent != null:
			navigation_agent.target_position = instance.goal_destination
		return

	_forced_destination = false
	_travel_timeout = -1.0
	_last_position = global_position
	evaluate_goal()


## Freeze this NPC in place for a conversation without discarding its goal,
## nav target or AI state. Selection/cancel unlocks it again.
func set_conversation_busy(busy: bool) -> void:
	_conversation_busy = busy
	if busy:
		velocity = Vector2.ZERO
	elif _has_pending_move:
		# Apply a class snap that arrived mid-conversation now that it is safe.
		_has_pending_move = false
		move_to(_pending_move_to)


## True while this NPC is already talking to someone (ticket 014/016 gate).
func is_conversation_busy() -> bool:
	return _conversation_busy


## True while this NPC is actively pursuing a goal or is in a conversation.
## Ticket 016 uses this as its "not-busy" gate for NPC-initiated interactions.
func is_busy() -> bool:
	return _conversation_busy or (_ai_enabled and instance != null and not instance.current_goal.is_empty())


## True while walking to a forced destination (class travel). Ticket 016 excludes
## these NPCs from initiation: they are effectively busy with the schedule. Ordinary
## hangout goals deliberately do NOT block initiation.
func is_forced_destination() -> bool:
	return _forced_destination


## Walk to an externally imposed destination (class travel). This bypasses
## NpcAi but reuses the same navigation agent, stall recovery and obstacle
## sliding; on arrival the body snaps exactly onto the destination.
func set_forced_destination(goal: String, destination: Vector2) -> void:
	_forced_destination = true
	_ai_enabled = true
	_arrival_pause = 0.0
	_stuck_elapsed = 0.0
	_fallback_elapsed = 0.0
	_using_fallback = false
	_force_fallback = false
	_avoid_elapsed = 0.0
	_travel_timeout = maxf(0.0, travel_timeout_sec)
	velocity = Vector2.ZERO
	if instance != null:
		instance.current_goal = goal
		instance.goal_destination = destination
	_last_position = global_position
	if navigation_agent != null:
		navigation_agent.target_position = destination


## Stop forced travel and clear its goal.
func clear_forced_destination() -> void:
	_forced_destination = false
	_ai_enabled = false
	_force_fallback = false
	_travel_timeout = -1.0
	velocity = Vector2.ZERO
	if instance != null:
		instance.current_goal = ""
		instance.goal_destination = Vector2.ZERO


## True when this NPC is already walking to `goal` (e.g. "class:classroom_a").
func is_forced_to(goal: String) -> bool:
	return _forced_destination and instance != null and instance.current_goal == goal


## Resume a saved in-flight goal through setup(). Ticket-013 review finding 3:
## goal_destination must be consumed on load, otherwise the serialized destination
## is dead data and NPCs stay motionless when a save is restored into free time.
func resume_saved_goal() -> void:
	if instance == null or instance.current_goal.is_empty():
		return
	if navigation_agent != null:
		navigation_agent.target_position = instance.goal_destination
	if instance.current_goal.begins_with("class:"):
		set_forced_destination(instance.current_goal, instance.goal_destination)


## Pick a new free-time goal through NpcAi and aim the navigation agent at it.
func evaluate_goal() -> void:
	if instance == null or _map == null:
		return
	var template: CharacterTemplate = instance.resolve_template()
	var result: Dictionary = NpcAi.select_goal(instance, template, _map, _seed_value, _eval_count)
	_eval_count += 1

	var goal: String = str(result.get("goal", ""))
	var destination_variant: Variant = result.get("destination", global_position)
	var destination: Vector2 = destination_variant if destination_variant is Vector2 else global_position

	instance.current_goal = goal
	instance.goal_destination = destination
	_stuck_elapsed = 0.0
	_fallback_elapsed = 0.0
	_arrival_pause = 0.0
	_using_fallback = false
	_force_fallback = false
	_avoid_elapsed = 0.0
	_last_position = global_position
	if navigation_agent != null:
		navigation_agent.target_position = destination


func _physics_process(delta: float) -> void:
	# ChunkManager drives managed NPCs at their tier's tick rate. Leaving this
	# guard here keeps directly-constructed NPCs working without the autoload.
	if chunk_managed:
		return
	_simulate(delta, false)


## ChunkManager tick-scheduler entry point. `coarse` selects far-tier
## straight-line stepping (no navmesh path, collision or obstacle sliding).
func simulate_tick(dt: float, coarse: bool) -> void:
	_simulate(dt, coarse)


## Hand this NPC's simulation over to (or back from) ChunkManager.
func set_chunk_managed(enabled: bool) -> void:
	chunk_managed = enabled
	if enabled:
		velocity = Vector2.ZERO


## After a promotion the authoritative position may have moved (e.g. a class
## snap performed while far). Re-aim the navigation agent so fine simulation
## resumes toward the saved goal instead of an old target.
func reconcile_after_promotion() -> void:
	velocity = Vector2.ZERO
	_last_position = global_position
	if instance != null:
		instance.coarse_position = global_position
		if not instance.current_goal.is_empty() and navigation_agent != null:
			navigation_agent.target_position = instance.goal_destination


## Shared simulation step for the legacy per-frame path (coarse=false) and the
## ChunkManager scheduler (coarse=true for far tier). All AI/state rules are
## identical; only the movement strategy differs.
func _simulate(delta: float, coarse: bool) -> void:
	if not _ai_enabled or instance == null or _conversation_busy:
		return

	if _arrival_pause > 0.0:
		_arrival_pause -= delta
		velocity = Vector2.ZERO
		return

	if instance.current_goal.is_empty():
		if _forced_destination:
			clear_forced_destination()
			return
		evaluate_goal()
		if instance.current_goal.is_empty():
			return  # map authors no hangout spots

	var destination: Vector2 = instance.goal_destination
	if _distance_to(destination) <= _target_distance():
		_arrive()
		return

	# Hard deadline for forced travel: snap onto the marker even if the nav
	# path oscillates and never satisfies progress-based stall detection.
	if _forced_destination:
		_travel_timeout -= delta
		if _travel_timeout <= 0.0:
			_arrive()
			return

	# Far tier: one straight-line step with the accumulated large dt. No navmesh
	# query, no physics collision and no obstacle sliding — coarse pathfinding
	# intentionally ignores furniture. Identity/state stay on `instance`.
	if coarse:
		_simulate_coarse(delta, destination)
		return

	# Prefer the navigation path. If the agent has no usable path — or a stall
	# forced the fallback — steer straight toward the destination until the goal
	# is re-evaluated. `_force_fallback` cannot be overwritten by a path that
	# exists but leads into a collider.
	var target_point: Vector2 = destination
	if navigation_agent != null and not _force_fallback:
		var next: Vector2 = navigation_agent.get_next_path_position()
		var path_usable: bool = (
			not navigation_agent.is_navigation_finished()
			and next.distance_to(global_position) > 0.01
		)
		if path_usable:
			_using_fallback = false
			target_point = next
		else:
			_using_fallback = true
	elif navigation_agent != null:
		_using_fallback = true

	var direction: Vector2 = target_point - global_position
	if direction.length_squared() > 0.0:
		direction = direction.normalized()

	# While recovering from a collision, slide along the obstacle surface in
	# the direction most aligned with the goal instead of pushing into it.
	if _avoid_elapsed > 0.0:
		_avoid_elapsed -= delta
		var to_avoid: Vector2 = _avoid_point - global_position
		if to_avoid.length_squared() > 1.0:
			direction = to_avoid.normalized()

	velocity = velocity.move_toward(direction * move_speed, move_acceleration * delta)
	move_and_slide()
	instance.position = global_position

	if _avoid_elapsed <= 0.0:
		for i in range(get_slide_collision_count()):
			var collision: KinematicCollision2D = get_slide_collision(i)
			if collision != null and collision.get_collider() != null:
				_start_avoidance(collision, direction)
				break

	_update_stall(delta)


## Straight-line far-tier step. Moves the body directly (no move_and_slide),
## mirroring the result into both the authoritative position and the runtime-only
## coarse position. The step is clamped so a large dt cannot overshoot the goal.
func _simulate_coarse(delta: float, destination: Vector2) -> void:
	var direction: Vector2 = destination - global_position
	var remaining: float = direction.length()
	if remaining <= _target_distance():
		_arrive()
		# Keep the coarse mirror consistent even on the arrival tick (review #4).
		instance.coarse_position = instance.position
		return
	var step_length: float = minf(move_speed * maxf(0.0, delta), remaining)
	if direction.length_squared() > 0.0:
		direction = direction.normalized()
	velocity = Vector2.ZERO
	global_position += direction * step_length
	instance.position = global_position
	instance.coarse_position = global_position
	_last_position = global_position


## Distance from the node to a world-space point.
func _distance_to(point: Vector2) -> float:
	return global_position.distance_to(point)


## Agent target distance, with a safe default for headless runs without an agent.
func _target_distance() -> float:
	return navigation_agent.target_desired_distance if navigation_agent != null else body_radius + 4.0


## Deflect around a solid obstacle. Sliding along the collider's tangent in the
## goal-aligned direction avoids the pinning that straight-line steering causes
## where the authored navmesh polygons overlap furniture colliders.
func _start_avoidance(collision: KinematicCollision2D, toward: Vector2) -> void:
	var normal: Vector2 = collision.get_normal()
	if normal.length_squared() <= 0.0:
		return
	var tangent: Vector2 = Vector2(-normal.y, normal.x).normalized()
	if tangent.dot(toward) < 0.0:
		tangent = -tangent
	_avoid_point = global_position + tangent * avoidance_distance
	_avoid_elapsed = avoidance_duration_sec


## Handle reaching the destination. Free-time goals pause briefly before the
## next one; forced travel snaps exactly onto the marker and stops.
func _arrive() -> void:
	velocity = Vector2.ZERO
	_stuck_elapsed = 0.0
	_fallback_elapsed = 0.0
	_using_fallback = false
	_force_fallback = false
	if _forced_destination:
		var destination: Vector2 = instance.goal_destination if instance != null else global_position
		global_position = destination
		if instance != null:
			instance.position = destination
		clear_forced_destination()
		return
	_arrival_pause = maxf(0.0, arrival_pause_sec)
	if instance != null:
		instance.current_goal = ""
		instance.goal_destination = Vector2.ZERO


## Detect a stalled NPC. After a no-progress window, ignore the nav path and
## steer straight toward the destination; if that also stalls for
## `fallback_timeout_sec`, re-evaluate the goal instead of freezing.
func _update_stall(delta: float) -> void:
	_stuck_elapsed += delta
	if _stuck_elapsed >= stuck_timeout_sec:
		if _last_position.distance_to(global_position) < 1.0:
			_force_fallback = true
			_using_fallback = true
			_fallback_elapsed = 0.0
		_last_position = global_position
		_stuck_elapsed = 0.0

	if _force_fallback:
		_fallback_elapsed += delta
		if _fallback_elapsed >= fallback_timeout_sec:
			if _forced_destination:
				_arrive()  # snap onto the class marker rather than pick a hangout
			else:
				evaluate_goal()


## Draw a simple two-tone circle so NPCs are visible without art assets.
func _draw() -> void:
	draw_circle(Vector2.ZERO, body_radius + 1.5, Color(0.12, 0.12, 0.16, 0.55))
	draw_circle(Vector2.ZERO, body_radius, body_color)


## Create the circular collider if the node was constructed in code (spawner
## creates bare Npc nodes, so there is no authored CollisionShape2D child).
func _ensure_collider() -> void:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null:
		return
	shape_node = CollisionShape2D.new()
	shape_node.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = body_radius
	shape_node.shape = circle
	add_child(shape_node)


## Attach a NavigationAgent2D if the scene has no authored one, and tune it to
## this body's size so it stops short of the destination instead of overshooting.
func _ensure_navigation_agent() -> void:
	if navigation_agent != null and is_instance_valid(navigation_agent):
		return
	navigation_agent = get_node_or_null("NavigationAgent2D") as NavigationAgent2D
	if navigation_agent == null:
		navigation_agent = NavigationAgent2D.new()
		navigation_agent.name = "NavigationAgent2D"
		add_child(navigation_agent)
	navigation_agent.path_desired_distance = body_radius + 2.0
	navigation_agent.target_desired_distance = body_radius + 4.0
	navigation_agent.avoidance_enabled = false


## Pick a stable palette colour from the instance id so the same npc always
## renders the same colour across runs and saves.
func _color_for(instance_id: String) -> Color:
	var index: int = absi(instance_id.hash()) % PALETTE.size()
	return PALETTE[index]
