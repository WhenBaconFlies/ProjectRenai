class_name InteractionComponent
extends Area2D

## InteractionComponent
##
## Player-side proximity + keypress trigger for the dialogue pipeline (ticket
## 014). As an Area2D child of Player it tracks NPCs (group "npc") that enter
## its radius and emits `interaction_requested` with the nearest one when the
## `interact` action (E / gamepad A) is pressed.
##
## It owns no dialogue state: Game.gd decides whether that interaction is
## allowed and disables the component while a pool is open.


## Emitted with the nearest NPC in range when the interact action is pressed.
signal interaction_requested(target: Npc)


## Radius of the proximity area, in pixels.
@export var interaction_radius: float = 28.0

## Input action checked for initiation. Registered defensively in _ready().
@export var interact_action: String = "interact"


var _candidates: Array = []
var _enabled: bool = true


func _ready() -> void:
	_ensure_collision_shape()
	_ensure_interact_action()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Generated shape so the component works even on a bare Area2D node (e.g. in
## headless tests). An authored shape in the scene is left untouched.
func _ensure_collision_shape() -> void:
	var shape_node: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		shape_node = CollisionShape2D.new()
		shape_node.name = "CollisionShape2D"
		add_child(shape_node)
	if shape_node.shape == null or not (shape_node.shape is CircleShape2D):
		var circle := CircleShape2D.new()
		circle.radius = interaction_radius
		shape_node.shape = circle


## Defensive fallback mirroring Player.gd: keep the trigger working if the
## project.godot [input] section is edited incorrectly.
func _ensure_interact_action() -> void:
	if not InputMap.has_action(interact_action):
		InputMap.add_action(interact_action, 0.5)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_E
		InputMap.action_add_event(interact_action, key)
		var button := InputEventJoypadButton.new()
		button.button_index = JOY_BUTTON_A
		InputMap.action_add_event(interact_action, button)


## Ignore input while a dialogue pool is open. Proximity is still tracked so
## the candidate list is current again as soon as the interaction ends.
func set_enabled(enabled: bool) -> void:
	_enabled = enabled


func is_enabled() -> bool:
	return _enabled


## Nearest live NPC currently inside the area, or null when none is in range.
func nearest_candidate() -> Npc:
	var best: Npc = null
	var best_distance: float = INF
	for item in _candidates:
		var npc: Npc = item as Npc
		if npc == null or not is_instance_valid(npc) or not npc.is_in_group(Npc.GROUP_NAME):
			continue
		var distance: float = global_position.distance_to(npc.global_position)
		if distance < best_distance:
			best_distance = distance
			best = npc
	return best


## UI consumes input first via _unhandled_input; hidden UI lets E reach here.
func _unhandled_input(event: InputEvent) -> void:
	if not _enabled or event.is_echo() or not event.is_pressed():
		return
	if not event.is_action_pressed(interact_action):
		return
	var target: Npc = nearest_candidate()
	if target != null:
		interaction_requested.emit(target)


func _on_body_entered(body: Node) -> void:
	var npc: Npc = body as Npc
	if npc == null or not npc.is_in_group(Npc.GROUP_NAME):
		return
	if not _candidates.has(npc):
		_candidates.append(npc)


func _on_body_exited(body: Node) -> void:
	_candidates.erase(body)
