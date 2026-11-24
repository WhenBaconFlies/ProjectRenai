class_name MapRenderer
extends Node2D

## MapRenderer
##
## Builds a playable world from a `Map` `.tres` resource at runtime:
##   * a single `TileMap` from `map.tile_ids` (using `map.tile_set`, or a generated
##     fallback tileset when none is provided). Godot's native culling handles
##     offscreen tiles, so tile cells are NEVER manually added or removed;
##   * one instantiated node per entry in `map.placed_objects`, grouped under a
##     `PlacedObjects` container into per-chunk children. Chunks are loaded around
##     the focus (normally the player) and unloaded beyond the far threshold;
##   * a `NavigationRegion2D` carrying `map.navigation_mesh`,
##   * a `Marker2D` named "SpawnPoint" at `map.spawn_point`.
##
## The spawn position is also exposed as `spawn_point` for spawners. A map with
## no placed objects renders without errors. Manual unload removes a chunk from
## the tree before queueing it for deletion, so a re-render within one frame
## never leaves duplicate nodes behind (ticket 008 review finding).


## The map resource this renderer is currently rendering. Assign before
## `_ready()` (via the editor export) or call `render(map)` at runtime.
@export var map: Map

## Node whose global position drives chunk loading. Wired to the player in
## Game.tscn; when empty, headless callers drive update_chunks() themselves.
@export var focus_path: NodePath = NodePath()

## Chebyshev radius (in chunks) that is always resident around the focus.
@export var load_radius_chunks: int = 5

## A resident chunk is freed only beyond this radius, giving one chunk of
## hysteresis against thrash at the boundary. Clamped to >= load radius.
@export var unload_radius_chunks: int = 6

## Emitted after a (re)render so map-driven children (e.g. ChunkGridOverlay) can
## refresh without reaching into this renderer's internals.
signal map_changed(map: Map)

## World-space spawn position taken from the rendered map. Read by spawners.
var spawn_point: Vector2 = Vector2.ZERO

## Child nodes created by `render()`.
var tile_map: TileMap
var placed_objects: Node2D
var navigation_region: NavigationRegion2D

## Chunk coord -> instantiated chunk node. The key set is the loaded chunk set.
var _loaded_chunks: Dictionary = {}

## Only these nodes are removed on re-render. Scene-declared children (e.g. the
## ChunkGridOverlay) must survive a map swap.
var _generated_children: Array[Node] = []

var _has_center: bool = false
var _last_center_chunk: Vector2i = Vector2i.ZERO


func _ready() -> void:
	if map != null:
		render(map)


## Build (or rebuild) the world from `p_map`. Safe to call repeatedly; any
## previously generated children are removed synchronously before replacements
## are added, then queued for deletion at the end of the frame.
func render(p_map: Map) -> void:
	map = p_map

	# Remove first, then queue: queue_free() alone leaves stale children in the
	# tree until the frame ends, which made an immediate re-render duplicate them.
	# Only generated nodes are touched; scene children like the overlay survive.
	for child in _generated_children:
		if is_instance_valid(child) and child.get_parent() == self:
			remove_child(child)
			child.queue_free()
	_generated_children.clear()
	tile_map = null
	placed_objects = null
	navigation_region = null
	_loaded_chunks.clear()
	_has_center = false
	_last_center_chunk = Vector2i.ZERO

	if map == null:
		push_warning("MapRenderer: no map to render")
		spawn_point = Vector2.ZERO
		map_changed.emit(null)
		return

	spawn_point = map.spawn_point

	# --- Tilemap (all tiles; Godot culls what is offscreen) ---
	tile_map = TileMap.new()
	tile_map.name = "TileMap"
	if map.tile_set != null:
		tile_map.tile_set = map.tile_set
	else:
		tile_map.tile_set = _build_fallback_tileset(map.tile_size)
	_add_generated(tile_map)

	var w: int = map.width
	var h: int = map.height
	var tile_ids: PackedInt32Array = map.tile_ids
	# Godot 4.2's set_cell() treats the default atlas coords (-1,-1) as "no tile",
	# so an explicit atlas coordinate is required. Flat tile_ids are interpreted
	# as atlas columns of the first source (the fallback tileset has one tile).
	var source_id: int = 0
	if tile_map.tile_set != null and tile_map.tile_set.get_source_count() > 0:
		source_id = tile_map.tile_set.get_source_id(0)
	for y in range(h):
		for x in range(w):
			var idx: int = y * w + x
			if idx >= tile_ids.size():
				continue
			var tid: int = tile_ids[idx]
			var coords := Vector2i(x, y)
			if tid < 0:
				tile_map.set_cell(0, coords, -1)
			else:
				tile_map.set_cell(0, coords, source_id, Vector2i(tid, 0))

	# --- Chunked placed objects ---
	placed_objects = Node2D.new()
	placed_objects.name = "PlacedObjects"
	_add_generated(placed_objects)

	# --- Navigation mesh (whole-map authored data, not per-frame render cost) ---
	navigation_region = NavigationRegion2D.new()
	navigation_region.name = "NavigationRegion2D"
	navigation_region.navigation_polygon = map.navigation_mesh
	_add_generated(navigation_region)

	# --- Spawn marker ---
	var marker := Marker2D.new()
	marker.name = "SpawnPoint"
	marker.position = spawn_point
	_add_generated(marker)

	map_changed.emit(map)
	# Until the focus node resolves, the authored spawn point is the best guess
	# for where the player will be; _process() corrects it on the first frame.
	update_chunks(spawn_point)


## Recompute the resident chunk set for a world-space focus position. Cheap
## no-op when the focus has not crossed into a new chunk.
func update_chunks(focus_world: Vector2) -> void:
	if map == null or placed_objects == null or map.get_chunk_count() <= 0:
		return
	var center: Vector2i = map.clamp_chunk(map.world_to_chunk(focus_world))
	if _has_center and center == _last_center_chunk:
		return
	_has_center = true
	_last_center_chunk = center

	var load_radius: int = maxi(1, load_radius_chunks)
	var unload_radius: int = maxi(load_radius, unload_radius_chunks)
	for cy in range(map.chunk_grid_height):
		for cx in range(map.chunk_grid_width):
			var chunk := Vector2i(cx, cy)
			var distance: int = maxi(absi(cx - center.x), absi(cy - center.y))
			if distance <= load_radius:
				if not _loaded_chunks.has(chunk):
					_load_chunk(chunk)
			elif _loaded_chunks.has(chunk) and distance > unload_radius:
				_unload_chunk(chunk)


## Instantiate every placed object whose clamped chunk is `chunk`.
func _load_chunk(chunk: Vector2i) -> void:
	var node := Node2D.new()
	node.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
	for entry in map.placed_objects:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var dict: Dictionary = entry
		var pos: Vector2 = _to_vector2(dict.get("position", Vector2.ZERO))
		# Out-of-grid objects clamp to the nearest valid chunk so none vanish.
		var object_chunk: Vector2i = map.clamp_chunk(map.world_to_chunk(pos))
		if object_chunk != chunk:
			continue
		var item: Item = dict.get("item", null) as Item
		var instance: Node = null
		if item != null and item.packed_scene != null:
			instance = item.packed_scene.instantiate()
		if instance == null:
			instance = Node2D.new()
		if instance is Node2D:
			instance.position = pos
		if item != null:
			_apply_item(instance, item, map.tile_size)
		node.add_child(instance)
	_loaded_chunks[chunk] = node
	placed_objects.add_child(node)


## Remove a chunk from the tree first, then free it at frame end.
func _unload_chunk(chunk: Vector2i) -> void:
	var node: Node2D = _loaded_chunks.get(chunk) as Node2D
	if node == null:
		return
	_loaded_chunks.erase(chunk)
	placed_objects.remove_child(node)
	node.queue_free()


## Loaded chunk coordinates, sorted row-major for deterministic diagnostics.
func get_loaded_chunks() -> Array:
	var keys: Array = _loaded_chunks.keys()
	keys.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	return keys


## Chunk node for `chunk`, or null when it is not currently loaded.
func get_chunk_node(chunk: Vector2i) -> Node2D:
	return _loaded_chunks.get(chunk) as Node2D


func _process(_delta: float) -> void:
	if map == null or focus_path.is_empty():
		return
	var focus: Node2D = get_node_or_null(focus_path) as Node2D
	if focus == null:
		return
	update_chunks(focus.global_position)


## Add a render-generated node and remember it for the next render() call.
func _add_generated(node: Node) -> void:
	add_child(node)
	_generated_children.append(node)


## Expose the spawn position explicitly for spawners that prefer a method call.
func get_spawn_point() -> Vector2:
	return spawn_point


func _to_vector2(v) -> Vector2:
	if v is Vector2:
		return v
	if v is Vector2i:
		return Vector2(v)
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO


func _build_fallback_tileset(tile_size: int) -> TileSet:
	var ts: int = tile_size if tile_size > 0 else 16
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(ts, ts)

	var img := Image.create(ts, ts, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.82, 0.82, 0.82))
	var tex := ImageTexture.create_from_image(img)

	var source := TileSetAtlasSource.new()
	source.texture = tex
	source.texture_region_size = Vector2i(ts, ts)
	source.create_tile(Vector2i.ZERO)
	tileset.add_source(source, 0)
	return tileset


func _apply_item(instance: Node, item: Item, tile_size: int) -> void:
	if not (instance is Node2D):
		return
	var node2d: Node2D = instance

	# Sprite data.
	if item.sprite != null:
		var spr := Sprite2D.new()
		spr.texture = item.sprite
		spr.offset = item.sprite_offset
		spr.scale = item.sprite_scale
		node2d.add_child(spr)
	else:
		# Placeholder visual so placed objects are visible even when no sprite
		# texture is authored (base content ships PackedScenes without sprites).
		var color := Color(0.55, 0.75, 0.55)
		match item.type:
			"wall":
				color = Color(0.35, 0.35, 0.4)
			"furniture":
				color = Color(0.62, 0.42, 0.22)
			"prop", "decoration":
				color = Color(0.5, 0.7, 0.85)
		var img := Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
		img.fill(color)
		var tex := ImageTexture.create_from_image(img)
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.offset = item.sprite_offset
		spr.scale = item.sprite_scale
		node2d.add_child(spr)

	# Collider data for solid items.
	if item.blocks_movement:
		var body := StaticBody2D.new()
		var shape_node := CollisionShape2D.new()
		var shape: Shape2D = item.collider_shape
		if shape == null:
			var rect := RectangleShape2D.new()
			rect.size = Vector2(tile_size, tile_size)
			shape = rect
		shape_node.shape = shape
		shape_node.position = item.collider_offset
		body.add_child(shape_node)
		node2d.add_child(body)
