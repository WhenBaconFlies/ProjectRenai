class_name Player
extends CharacterBody2D

## Player
##
## Free 2D movement controller for the v1 vertical slice. Reads a 2D input
## vector (keyboard WASD/arrows or gamepad left stick), steers a CharacterBody2D
## with acceleration/friction and `move_and_slide()` so collision against the
## map's wall/furniture StaticBody2D nodes is handled by Godot physics.
##
## The player's start position is taken from the rendered map's spawn point,
## and a small generated circle is drawn as a placeholder sprite (v1 ships no
## character art). The `player` group marks this node for the future
## InteractionComponent.

## Group tag used by interaction/dialogue systems to find the player.
const GROUP_NAME := "player"


## Maximum movement speed in pixels per second.
@export var speed: float = 110.0

## How quickly the body reaches the target velocity (pixels per second squared).
@export var acceleration: float = 1200.0

## How quickly the body stops when no input is held (pixels per second squared).
@export var friction: float = 1600.0

## Fill colour of the placeholder body.
@export var body_color: Color = Color(0.95, 0.72, 0.35)

## Colour of the small facing indicator drawn on the body.
@export var facing_color: Color = Color(0.18, 0.12, 0.06)

## Radius of the physics collider and drawn body (pixels).
@export var body_radius: float = 6.0


## Last non-zero movement direction; used to draw the facing dot.
var _facing: Vector2 = Vector2.RIGHT


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_ensure_input_actions()
	# Deferred so the sibling MapRenderer has run its _ready()/render() first.
	call_deferred("_snap_to_spawn")


## Snap to the map's authored spawn point. Falls back to the scene position if
## no renderer/map is present (e.g. an empty test scene).
func _snap_to_spawn() -> void:
	var renderer := get_node_or_null("../MapRenderer") as MapRenderer
	if renderer == null or renderer.map == null:
		push_warning("Player: no rendered map found; keeping scene position")
		return
	global_position = renderer.get_spawn_point()
	velocity = Vector2.ZERO


## Physics tick: build the input vector, steer velocity, then move with
## collision. `Input.get_vector` normalises diagonals and reads gamepad sticks.
func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	var target_velocity := input_vector * speed
	var rate: float = acceleration if input_vector.length_squared() > 0.0 else friction
	velocity = velocity.move_toward(target_velocity, rate * delta)

	if input_vector.length_squared() > 0.0:
		var new_facing := input_vector.normalized()
		if new_facing.distance_squared_to(_facing) > 0.01:
			_facing = new_facing
			queue_redraw()

	move_and_slide()


## Draw a simple two-tone circle so the player is visible without art assets.
func _draw() -> void:
	draw_circle(Vector2.ZERO, body_radius + 1.5, Color(0.12, 0.12, 0.16, 0.55))
	draw_circle(Vector2.ZERO, body_radius, body_color)
	draw_circle(_facing * (body_radius * 0.45), 1.8, facing_color)


## Defensive fallback: register any movement action missing from ProjectSettings
## so the controller still works if project.godot's [input] section is edited
## incorrectly. Normal runs find the actions already defined there.
func _ensure_input_actions() -> void:
	# Only build the fallback actions when none exist; project.godot normally
	# defines them already, and we must not duplicate its events.
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		if InputMap.has_action(action):
			return
		InputMap.add_action(action, 0.5)

	_register_key("move_left", KEY_A)
	_register_key("move_left", KEY_LEFT)
	_register_key("move_right", KEY_D)
	_register_key("move_right", KEY_RIGHT)
	_register_key("move_up", KEY_W)
	_register_key("move_up", KEY_UP)
	_register_key("move_down", KEY_S)
	_register_key("move_down", KEY_DOWN)
	_register_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_register_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_register_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_register_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_register_button("move_left", JOY_BUTTON_DPAD_LEFT)
	_register_button("move_right", JOY_BUTTON_DPAD_RIGHT)
	_register_button("move_up", JOY_BUTTON_DPAD_UP)
	_register_button("move_down", JOY_BUTTON_DPAD_DOWN)


func _register_key(action: String, keycode: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


func _register_axis(action: String, axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action, event)


func _register_button(action: String, button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)
