class_name FollowCamera
extends Camera2D

## FollowCamera
##
## Smooth-follow camera for the v1 slice. The camera is a CHILD of the player;
## its local offset is the lag between the smoothed world position and the
## player's current world position.
##
## Smoothing is done manually in _physics_process (Camera2D's built-in
## position smoothing is deliberately OFF). The player also moves in physics
## ticks, so both update in lockstep: the player stays fixed on screen between
## ticks instead of stepping and then drifting back as the camera interpolates
## every render frame (measured as a ~14 px sawtooth at 8x zoom).
##
## Do not write `global_position` from a script every frame while Camera2D's
## built-in smoothing is enabled — that fights its internal state and was
## observed to invert the follow direction.
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

## Exponential smoothing rate (higher = tighter follow, less lag).
@export var smoothing_speed: float = 10.0

## Whether to keep the view inside the rendered map's pixel bounds.
@export var clamp_to_map: bool = true


var _renderer: MapRenderer
var _map_pixel_size: Vector2i = Vector2i.ZERO
var _last_map: Map = null
var _player_parent: Node2D
var _smooth_world: Vector2 = Vector2.ZERO
var _follow_initialized: bool = false


func _ready() -> void:
	# Local zero: the parent (player) supplies the world position.
	position = Vector2.ZERO
	zoom = Vector2(zoom_level, zoom_level)
	# Manual smoothing happens in _physics_process, in lockstep with the player.
	position_smoothing_enabled = false
	limit_smoothed = false
	# Defer so the renderer (an ancestor's sibling) has completed _ready().
	call_deferred("_resolve_nodes")


## Resolve the renderer and derive camera limits from the rendered map.
func _resolve_nodes() -> void:
	_player_parent = get_parent() as Node2D
	if _player_parent == null:
		push_warning("FollowCamera: parent is not a Node2D; camera cannot follow")
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


## Smooth toward the player's world position. Running in the physics tick
## keeps the camera and player in lockstep, avoiding per-frame jitter.
func _physics_process(delta: float) -> void:
	if _renderer != null and _renderer.map != _last_map:
		_refresh_map_bounds()
	if _player_parent == null:
		return

	var target: Vector2 = _player_parent.global_position
	if not _follow_initialized:
		_smooth_world = target
		_follow_initialized = true
	else:
		var weight: float = 1.0 - exp(-smoothing_speed * delta)
		_smooth_world = _smooth_world.lerp(target, weight)

	# Camera is parented to the player: local offset = desired - parent.
	position = _smooth_world - target
