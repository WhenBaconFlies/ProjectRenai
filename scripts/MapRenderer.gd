class_name MapRenderer
extends Node2D

## MapRenderer
##
## Builds a playable world from a `Map` `.tres` resource at runtime:
##   * a `TileMap` from `map.tile_ids` (using `map.tile_set`, or a generated
##     fallback tileset when none is provided),
##   * one instantiated node per entry in `map.placed_objects`, built from the
##     entry's `Item.packed_scene` (with sprite/collider data applied),
##   * a `NavigationRegion2D` carrying `map.navigation_mesh`,
##   * a `Marker2D` named "SpawnPoint" at `map.spawn_point`.
##
## The spawn position is also exposed as `spawn_point` for spawners. A map with
## no placed objects renders without errors.


## The map resource this renderer is currently rendering. Assign before
## `_ready()` (via the editor export) or call `render(map)` at runtime.
@export var map: Map

## World-space spawn position taken from the rendered map. Read by spawners.
var spawn_point: Vector2 = Vector2.ZERO

## Child nodes created by `render()`.
var tile_map: TileMap
var placed_objects: Node2D
var navigation_region: NavigationRegion2D


func _ready() -> void:
	if map != null:
		render(map)


## Build (or rebuild) the world from `p_map`. Safe to call repeatedly; any
## previously generated children are freed first.
func render(p_map: Map) -> void:
	map = p_map

	# Free previously generated children.
	for child in get_children():
		child.queue_free()
	tile_map = null
	placed_objects = null
	navigation_region = null

	if map == null:
		push_warning("MapRenderer: no map to render")
		spawn_point = Vector2.ZERO
		return

	spawn_point = map.spawn_point

	# --- Tilemap ---
	tile_map = TileMap.new()
	tile_map.name = "TileMap"
	if map.tile_set != null:
		tile_map.tile_set = map.tile_set
	else:
		tile_map.tile_set = _build_fallback_tileset(map.tile_size)
	add_child(tile_map)

	var w: int = map.width
	var h: int = map.height
	var tile_ids: PackedInt32Array = map.tile_ids
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
				tile_map.set_cell(0, coords, tid)

	# --- Placed objects ---
	placed_objects = Node2D.new()
	placed_objects.name = "PlacedObjects"
	add_child(placed_objects)

	for entry in map.placed_objects:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var dict: Dictionary = entry
		var pos: Vector2 = _to_vector2(dict.get("position", Vector2.ZERO))
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
		placed_objects.add_child(instance)

	# --- Navigation mesh ---
	navigation_region = NavigationRegion2D.new()
	navigation_region.name = "NavigationRegion2D"
	navigation_region.navigation_polygon = map.navigation_mesh
	add_child(navigation_region)

	# --- Spawn marker ---
	var marker := Marker2D.new()
	marker.name = "SpawnPoint"
	marker.position = spawn_point
	add_child(marker)


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
