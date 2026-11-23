class_name Minimap
extends Control

## Minimap
##
## Data-first minimap for the v1 slice. Instead of a second Camera2D/SubViewport,
## this Control reads the Map resource directly in `_draw()`: floor tiles come
## from `Map.tile_ids`, solid objects from `placed_objects` entries whose Item
## has `blocks_movement`, and the player's live position is drawn as a dot.
##
## Everything is uniformly scaled into a fixed panel anchored to a screen
## corner. Redraws are requested only when the player moves past a small
## threshold or the rendered map changes, so the cost at 60 fps is negligible.
## NPC dots can be added later by reading NPC positions — no scene or viewport
## changes needed.

## NodePath (relative to this Control) of the player dot target.
@export var player_path: NodePath = ^"../../Player"

## NodePath (relative to this Control) of the MapRenderer supplying map data.
@export var map_renderer_path: NodePath = ^"../../MapRenderer"

## Blank margin inside the panel, in pixels.
@export var padding: float = 8.0

## Colour of walkable floor squares.
@export var floor_color: Color = Color(0.34, 0.39, 0.44)

## Colour of wall squares.
@export var wall_color: Color = Color(0.16, 0.17, 0.22)

## Colour of solid furniture squares.
@export var furniture_color: Color = Color(0.48, 0.34, 0.21)

## Colour of the player marker.
@export var player_color: Color = Color(1.0, 0.86, 0.32)

## Minimum player movement (pixels) before the minimap redraws.
@export var redraw_move_threshold: float = 0.5


var _player: Node2D
var _renderer: MapRenderer
var _last_map: Map = null
var _last_player_pos: Vector2 = Vector2.ZERO
var _has_drawn: bool = false


func _ready() -> void:
	# The minimap is read-only; let clicks pass through to the game.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Defer so sibling nodes have completed _ready().
	call_deferred("_resolve_nodes")


## Resolve node references with deferred, tree-safe lookups.
func _resolve_nodes() -> void:
	_player = get_node_or_null(player_path) as Node2D
	if _player == null:
		push_warning("Minimap: player node not found; player dot will be hidden")
	_renderer = get_node_or_null(map_renderer_path) as MapRenderer
	if _renderer == null:
		push_warning("Minimap: map renderer not found; map will be empty")
	queue_redraw()


## Request a redraw only when something visible actually changed.
func _process(_delta: float) -> void:
	var map: Map = _renderer.map if _renderer != null else null
	if map != _last_map:
		_last_map = map
		queue_redraw()
		return

	if _player == null:
		return
	var pos: Vector2 = _player.global_position
	if not _has_drawn or pos.distance_squared_to(_last_player_pos) >= (
		redraw_move_threshold * redraw_move_threshold
	):
		_last_player_pos = pos
		_has_drawn = true
		queue_redraw()


## Draw the panel, map tiles, solid objects, and the player marker.
func _draw() -> void:
	var panel := Rect2(Vector2.ZERO, size)
	draw_rect(panel, Color(0.04, 0.05, 0.07, 0.78), true)
	draw_rect(panel, Color(0.75, 0.8, 0.9, 0.45), false, 1.0)

	var map: Map = _renderer.map if _renderer != null else null
	if map == null or map.width <= 0 or map.height <= 0 or map.tile_size <= 0:
		return

	var map_size := Vector2(map.width * map.tile_size, map.height * map.tile_size)
	var available := size - Vector2(padding * 2.0, padding * 2.0)
	if available.x <= 0.0 or available.y <= 0.0:
		return

	var scale: float = minf(available.x / map_size.x, available.y / map_size.y)
	var origin: Vector2 = (size - map_size * scale) * 0.5

	# Floor squares from the authored tile grid (-1 means empty).
	for y in range(map.height):
		for x in range(map.width):
			var idx: int = y * map.width + x
			if idx >= map.tile_ids.size() or map.tile_ids[idx] < 0:
				continue
			var cell_rect := Rect2(
				origin + Vector2(x * map.tile_size, y * map.tile_size) * scale,
				Vector2(map.tile_size * scale, map.tile_size * scale)
			)
			draw_rect(cell_rect, floor_color, true)

	# Solid placed objects (walls and blocking furniture).
	for entry in map.placed_objects:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var dict: Dictionary = entry
		var item: Item = dict.get("item", null) as Item
		if item == null or not item.blocks_movement:
			continue
		var pos := _to_vector2(dict.get("position", Vector2.ZERO))
		var collider := _collider_rect(item, map.tile_size)
		var rect := Rect2(
			origin + (pos + collider.position) * scale,
			collider.size * scale
		)
		var color: Color = wall_color if item.type == "wall" else furniture_color
		draw_rect(rect, color, true)

	# Player marker on top of everything else.
	if _player != null:
		draw_circle(origin + _player.global_position * scale, 3.0, player_color)


## Local-space rectangle of an item's authored collider, matching MapRenderer's
## physics shape (offset applied, tile-size rectangle when no shape is authored).
func _collider_rect(item: Item, tile_size: int) -> Rect2:
	var size := Vector2(tile_size, tile_size)
	var shape: Shape2D = item.collider_shape
	if shape is RectangleShape2D:
		size = (shape as RectangleShape2D).size
	elif shape is CircleShape2D:
		var radius: float = (shape as CircleShape2D).radius
		size = Vector2(radius * 2.0, radius * 2.0)
	elif shape is CapsuleShape2D:
		var capsule: CapsuleShape2D = shape as CapsuleShape2D
		size = Vector2(capsule.radius * 2.0, capsule.height)
	return Rect2(item.collider_offset - size * 0.5, size)


## Convert the placed-object position variants (Vector2/Vector2i/Array) to Vector2.
func _to_vector2(value) -> Vector2:
	if value is Vector2:
		return value
	if value is Vector2i:
		return Vector2(value)
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
