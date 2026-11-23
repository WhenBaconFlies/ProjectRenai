class_name Map
extends Resource

## Map
##
## A map stored as a `.tres` resource. Carries tile data (a grid of tile IDs),
## placed objects (a list of {position, item resource ref}), a spawn point,
## navigation mesh data, and chunk-loading seams (`chunk_size` + derived chunk
## grid dimensions). A developer can create and save instances of this in the
## Godot editor.


## --- Identity ---

## Stable map id (e.g. "map:school_day1").
@export var id: String = ""

## Human-readable map name.
@export var display_name: String = ""


## --- Tile data ---

## Tile grid width in tiles.
@export var width: int = 0

## Tile grid height in tiles.
@export var height: int = 0

## Tile size in pixels (used by the renderer when no tileset is provided).
@export var tile_size: int = 16

## Optional TileSet used by the renderer to draw `tile_ids`.
@export var tile_set: TileSet

## Flat, row-major grid of tile IDs (length should be width * height).
## A value of -1 means "empty/no tile".
@export var tile_ids: PackedInt32Array = PackedInt32Array()


## --- Placed objects ---
## Array of dictionaries: { "position": Vector2/Vector2i, "item": Item }.
## The renderer instantiates each entry's item `packed_scene` at `position`.

@export var placed_objects: Array = []


## --- Spawn point ---

## World-space spawn position used to place the player (and NPCs) on load.
@export var spawn_point: Vector2 = Vector2.ZERO


## --- Named markers ----------------------------------------------------------

## Named world-space locations used by per-instance NPC schedules. Keys are
## stable marker names (e.g. "classroom_a"); values are world-space Vector2s.
## Schedules store the name, not the position, so a marker can be moved in the
## map resource without rewriting any NPC schedule.
@export var markers: Dictionary = {}


## --- Navigation mesh ---

## Baked navigation polygon used by NavigationAgent2D for pathfinding.
@export var navigation_mesh: NavigationPolygon


## --- Chunk loading (post-v1 seams) ---

## Chunk size in tiles. Fixed grid; chunk grid dimensions are derived below.
@export var chunk_size: int = 32


## --- Derived chunk grid dimensions (read-only) ---

## Number of chunks along the X axis (ceil(width / chunk_size)).
var chunk_grid_width: int:
	get:
		if chunk_size <= 0 or width <= 0:
			return 0
		return (width + chunk_size - 1) / chunk_size

## Number of chunks along the Y axis (ceil(height / chunk_size)).
var chunk_grid_height: int:
	get:
		if chunk_size <= 0 or height <= 0:
			return 0
		return (height + chunk_size - 1) / chunk_size

## Derived chunk grid dimensions as a Vector2i (width, height in chunks).
var chunk_grid_size: Vector2i:
	get:
		return Vector2i(chunk_grid_width, chunk_grid_height)


## --- Marker read API --------------------------------------------------------

## True when `name` is an authored marker on this map.
func has_marker(marker_name: String) -> bool:
	return markers.has(marker_name)


## World-space position of marker `name`, or `fallback` when absent. Tolerates
## Vector2, Vector2i and 2-element arrays so hand-authored resources are safe.
func get_marker(marker_name: String, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if not markers.has(marker_name):
		return fallback
	var value: Variant = markers[marker_name]
	if value is Vector2:
		return value
	if value is Vector2i:
		return Vector2(value)
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


## All authored marker names, sorted for deterministic schedule generation.
func get_marker_names() -> Array:
	var names: Array = []
	for key in markers.keys():
		names.append(str(key))
	names.sort()
	return names
