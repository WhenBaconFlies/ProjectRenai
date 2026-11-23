class_name Npc
extends CharacterBody2D

## Npc
##
## Scene-side representation of one NpcInstance. The instance resource owns the
## authoritative data (position, schedule, meters, ...); this node draws a
## generated placeholder body and mirrors position changes into the instance.
## It is a CharacterBody2D with a circular collider so ticket 013 can attach a
## NavigationAgent2D for free-time AI without changing the node type.

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

## The runtime instance this node represents. Set once via setup().
var instance: NpcInstance = null


## Bind an instance, place the node at its saved/current position, and ensure a
## collider exists. Safe to call before the node enters the scene tree.
func setup(p_instance: NpcInstance) -> void:
	instance = p_instance
	add_to_group(GROUP_NAME)
	if instance != null:
		global_position = instance.position
		body_color = _color_for(instance.instance_id)
	_ensure_collider()
	queue_redraw()


## Move to a world-space position and keep the instance authoritative position
## in sync. Used on period changes (instant reposition in v1).
func move_to(p_position: Vector2) -> void:
	global_position = p_position
	if instance != null:
		instance.position = p_position


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


## Pick a stable palette colour from the instance id so the same npc always
## renders the same colour across runs and saves.
func _color_for(instance_id: String) -> Color:
	var index: int = absi(instance_id.hash()) % PALETTE.size()
	return PALETTE[index]
