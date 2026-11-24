class_name ChunkGridOverlay
extends Node2D

## ChunkGridOverlay
##
## Reusable Node2D that draws the chunk boundaries derived from a `Map`
## (`chunk_size` tiles × `tile_size` pixels). v1 has no map editor, so it is
## wired under MapRenderer in Game.tscn, hidden by default, and toggled with the
## `toggle_chunk_grid` (F6) action. A future editor can reuse this component by
## assigning `map` directly. Drawing is data-only: it never touches map state.


## Map whose chunk grid is drawn. When left empty in the scene, it is inherited
## from a parent MapRenderer and kept in sync via its map_changed signal.
@export var map: Map

## Colour of the chunk boundary lines and coordinate labels.
@export var line_color: Color = Color(0.25, 0.9, 1.0, 0.8)

## Draw "(x,y)" in the top-left corner of each chunk.
@export var draw_labels: bool = true

## Input action that toggles visibility. Empty disables keyboard toggling.
@export var toggle_action: String = "toggle_chunk_grid"

## Hidden until a developer turns it on (debug overlay, not game art).
@export var hidden_by_default: bool = true


func _ready() -> void:
	# Draw above tiles/objects even though the scene declares this child first
	# and render() appends its generated nodes afterwards.
	z_index = 10
	if map == null:
		var parent: Node = get_parent()
		if parent is MapRenderer:
			map = (parent as MapRenderer).map
		if parent != null and parent.has_signal("map_changed") and not parent.is_connected("map_changed", Callable(self, "_on_map_changed")):
			parent.connect("map_changed", Callable(self, "_on_map_changed"))
	visible = not hidden_by_default
	queue_redraw()


## Assign (or reassign) the map and request a redraw.
func set_map(new_map: Map) -> void:
	map = new_map
	queue_redraw()


## Show/hide seam for the input action and for headless verification.
func toggle() -> void:
	visible = not visible
	queue_redraw()


## Follow map swaps in the parent renderer without a scene-level wire.
func _on_map_changed(new_map: Map) -> void:
	set_map(new_map)


func _unhandled_input(event: InputEvent) -> void:
	if toggle_action.is_empty() or not InputMap.has_action(toggle_action):
		return
	if event.is_action_pressed(toggle_action):
		toggle()


## Draw grid lines across the derived chunk grid. Uses the fallback UI font for
## labels so no authored theme/font asset is required.
func _draw() -> void:
	if map == null:
		return
	var chunk_px: int = map.chunk_pixel_size()
	if chunk_px <= 0:
		return
	var grid_width: int = map.chunk_grid_width
	var grid_height: int = map.chunk_grid_height
	var total_width: float = float(grid_width * chunk_px)
	var total_height: float = float(grid_height * chunk_px)

	for x in range(grid_width + 1):
		var px: float = float(x * chunk_px)
		draw_line(Vector2(px, 0.0), Vector2(px, total_height), line_color)
	for y in range(grid_height + 1):
		var py: float = float(y * chunk_px)
		draw_line(Vector2(0.0, py), Vector2(total_width, py), line_color)

	if draw_labels and ThemeDB.fallback_font != null:
		for cy in range(grid_height):
			for cx in range(grid_width):
				var label_pos: Vector2 = Vector2(cx * chunk_px + 4, cy * chunk_px + 12)
				draw_string(
					ThemeDB.fallback_font, label_pos, "(%d,%d)" % [cx, cy],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, line_color
				)
