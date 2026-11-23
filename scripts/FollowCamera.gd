class_name FollowCamera
extends Camera2D

## FollowCamera
##
## Smooth-follow camera for the v1 slice. Each frame the camera targets the
## player's position and relies on Camera2D's built-in position smoothing so
## motion stays fluid even while the player moves in discrete physics ticks.
##
## The map is tiny (160x128 px on the default resource), so the camera is
## zoomed in by default to make follow visible and to make the minimap useful.
## Camera limits are derived from the rendered map's pixel dimensions and
## applied to the smoothed position to avoid overshooting past map edges.

## NodePath (relative to this camera) of the player to follow.
@export var player_path: NodePath = ^"../Player"

## NodePath (relative to this camera) of the MapRenderer supplying map bounds.
@export var map_renderer_path: NodePath = ^"../MapRenderer"

## Positive values zoom in. 8 keeps the default 160x128 map larger than the
## viewport so the camera actually travels as the player moves.
@export var zoom_level: float = 8.0

## Camera2D position smoothing speed (higher = tighter follow, less lag).
@export var smoothing_speed: float = 10.0

## Whether to keep the view inside the rendered map's pixel bounds.
@export var clamp_to_map: bool = true


var _player: Node2D
var _renderer: MapRenderer
var _map_pixel_size: Vector2i = Vector2i.ZERO


func _ready() -> void:
	zoom = Vector2(zoom_level, zoom_level)
	position_smoothing_enabled = true
	position_smoothing_speed = smoothing_speed
	# Apply limits after smoothing so the view never drifts past the map edge.
	limit_smoothed = true
	# Defer so sibling nodes (player + renderer) have completed _ready().
	call_deferred("_resolve_nodes")


## Resolve node references and derive camera limits from the rendered map.
func _resolve_nodes() -> void:
	_player = get_node_or_null(player_path) as Node2D
	if _player == null:
		push_warning("FollowCamera: player node not found; camera will not follow")

	_renderer = get_node_or_null(map_renderer_path) as MapRenderer
	if _renderer == null or _renderer.map == null:
		push_warning("FollowCamera: map renderer/map not found; no camera limits")
		return

	_map_pixel_size = Vector2i(
		_renderer.map.width * _renderer.map.tile_size,
		_renderer.map.height * _renderer.map.tile_size
	)
	_apply_limits()
	# Re-derive limits if the window is resized (view size affects margins).
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.connect(_on_viewport_resized)


## Clamp the camera so the visible rectangle stays inside the map. Godot's raw
## limits only clamp the camera centre; at zoom > 1 that would still reveal
## empty space past the map edges, so the margins account for zoom/viewport.
func _apply_limits() -> void:
	if not clamp_to_map or _map_pixel_size.x <= 0 or _map_pixel_size.y <= 0:
		return
	var view_size: Vector2 = get_viewport_rect().size
	var half_view_x: float = view_size.x / (2.0 * maxf(absf(zoom.x), 0.001))
	var half_view_y: float = view_size.y / (2.0 * maxf(absf(zoom.y), 0.001))
	limit_left = _axis_limit(_map_pixel_size.x, half_view_x)
	limit_right = _map_pixel_size.x - limit_left
	limit_top = _axis_limit(_map_pixel_size.y, half_view_y)
	limit_bottom = _map_pixel_size.y - limit_top


## Low bound for one axis. If the map is smaller than the view, pin the camera
## to the map's centre; otherwise keep the view inside the map bounds.
func _axis_limit(map_extent: int, half_view: float) -> int:
	if float(map_extent) <= half_view * 2.0:
		return int(round(float(map_extent) * 0.5))
	return int(round(half_view))


func _on_viewport_resized() -> void:
	_apply_limits()


## Track the player. Camera2D smoothing interpolates toward this target.
func _process(_delta: float) -> void:
	if _player != null:
		global_position = _player.global_position
