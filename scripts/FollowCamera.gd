class_name FollowCamera
extends Camera2D

## FollowCamera
##
## Smooth-follow camera for the v1 slice. The camera is a CHILD of the player,
## so it inherits the player's transform automatically; Camera2D's built-in
## position smoothing adds the lag that makes motion feel fluid.
##
## Important: do not write `global_position` from a script every frame while
## smoothing is enabled. That fights Camera2D's internal smoothing state and
## makes the view drift the wrong way (observed as an inverted follow). Moving
## the parent is the intended way to drive a smoothed Camera2D.
##
## The map is tiny (160x128 px on the default resource), so the camera is
## zoomed in by default to make follow visible and to make the minimap useful.
## Camera limits are the rendered map's raw pixel bounds. Godot already
## accounts for viewport size and zoom when clamping, so insetting the limits
## by half the view double-compensates and breaks follow (verified: an inset
## range made the camera drift opposite to the player).

## NodePath (relative to this camera) of the MapRenderer supplying map bounds.
@export var map_renderer_path: NodePath = ^"../../MapRenderer"

## Positive values zoom in. 8 keeps the default 160x128 map larger than the
## viewport so the camera actually travels as the player moves.
@export var zoom_level: float = 8.0

## Camera2D position smoothing speed (higher = tighter follow, less lag).
@export var smoothing_speed: float = 10.0

## Whether to keep the view inside the rendered map's pixel bounds.
@export var clamp_to_map: bool = true


var _renderer: MapRenderer
var _map_pixel_size: Vector2i = Vector2i.ZERO
var _last_map: Map = null


func _ready() -> void:
	# Local zero: the parent (player) supplies the world position.
	position = Vector2.ZERO
	zoom = Vector2(zoom_level, zoom_level)
	position_smoothing_enabled = true
	position_smoothing_speed = smoothing_speed
	# Apply limits after smoothing so the view never drifts past the map edge.
	limit_smoothed = true
	# Defer so the renderer (an ancestor's sibling) has completed _ready().
	call_deferred("_resolve_nodes")


## Resolve the renderer and derive camera limits from the rendered map.
func _resolve_nodes() -> void:
	_renderer = get_node_or_null(map_renderer_path) as MapRenderer
	_refresh_map_bounds()
	# Re-derive limits if the window is resized (view size affects margins).
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.connect(_on_viewport_resized)


## Re-read the renderer's current map and recalculate bounds. Called on load
## and on map swaps (MapRenderer.render is re-entrant). Resize reuses the
## cached extents via _on_viewport_resized().
func _refresh_map_bounds() -> void:
	if _renderer == null or _renderer.map == null:
		_map_pixel_size = Vector2i.ZERO
		_last_map = null
		push_warning("FollowCamera: map renderer/map not found; no camera limits")
		return
	_last_map = _renderer.map
	_map_pixel_size = Vector2i(
		_last_map.width * _last_map.tile_size,
		_last_map.height * _last_map.tile_size
	)
	_apply_limits()


## Clamp the view to the map's raw pixel bounds. Godot's Camera2D clamps the
## centre using the viewport and zoom itself, so passing raw bounds keeps the
## visible rectangle inside the map without any manual margin arithmetic.
func _apply_limits() -> void:
	if not clamp_to_map or _map_pixel_size.x <= 0 or _map_pixel_size.y <= 0:
		return
	limit_left = 0
	limit_top = 0
	limit_right = _map_pixel_size.x
	limit_bottom = _map_pixel_size.y


func _on_viewport_resized() -> void:
	# Raw bounds are viewport-independent; kept so external changes still apply.
	_apply_limits()


## Only map swaps need attention here; following is handled by the parent.
func _process(_delta: float) -> void:
	if _renderer != null and _renderer.map != _last_map:
		_refresh_map_bounds()
