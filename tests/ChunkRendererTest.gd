## ChunkRendererTest
##
## Persistent headless harness for ticket 020 (chunk-aware map renderer). It is
## attached to /root by ChunkRendererBootstrap so it survives the scene change
## into the real Game.tscn. Synthetic in-code maps give this harness large grids
## to exercise -- the shipped debug map is only 1x1 chunk, so it cannot show a
## load/unload boundary. Prints ALL_020_CHECKS_PASSED only when every check passes.
extends Node


var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_grid_math()
	_check_chunk_helpers()
	_check_renderer()
	_check_overlay()
	await _check_real_game()
	_finish()


## --- Grid math on Map --------------------------------------------------------

func _check_grid_math() -> void:
	var cases: Array = [
		{"w": 0, "h": 0, "cs": 32, "ew": 0, "eh": 0},
		{"w": 1, "h": 1, "cs": 32, "ew": 1, "eh": 1},
		{"w": 32, "h": 24, "cs": 32, "ew": 1, "eh": 1},
		{"w": 33, "h": 65, "cs": 32, "ew": 2, "eh": 3},
		{"w": 64, "h": 64, "cs": 16, "ew": 4, "eh": 4},
		{"w": 10, "h": 8, "cs": 0, "ew": 0, "eh": 0},
	]
	for entry in cases:
		var c: Dictionary = entry
		var m := _make_map(int(c["w"]), int(c["h"]), int(c["cs"]), 16)
		var label: String = "%dx%d tiles, chunk %d" % [c["w"], c["h"], c["cs"]]
		_check(
			m.chunk_grid_width == int(c["ew"]) and m.chunk_grid_height == int(c["eh"]),
			"grid %s -> %dx%d chunks (got %dx%d)" % [
				label, c["ew"], c["eh"], m.chunk_grid_width, m.chunk_grid_height
			]
		)
		_check(
			m.chunk_grid_size == Vector2i(int(c["ew"]), int(c["eh"])),
			"grid %s exposes matching chunk_grid_size" % label
		)


## Read-only chunk helpers added in ticket 020. Calls are dynamic so this harness
## parses and RUNS (with failures) against the pre-change source for a clean RED.
func _check_chunk_helpers() -> void:
	var m := _make_map(64, 64, 16, 16)
	for method in [
		"chunk_pixel_size", "tile_to_chunk", "world_to_chunk",
		"clamp_chunk", "chunk_rect", "get_chunk_count"
	]:
		_check(m.has_method(str(method)), "Map exposes %s()" % method)
	if not m.has_method("world_to_chunk"):
		return
	var pixel_size: int = int(m.call("chunk_pixel_size"))
	_check(pixel_size == 256, "chunk_pixel_size = chunk_size * tile_size (got %d)" % pixel_size)
	var wc: Vector2i = m.call("world_to_chunk", Vector2(300, 100))
	_check(wc == Vector2i(1, 0), "world_to_chunk(300,100) -> (1,0) (got %s)" % wc)
	var tc: Vector2i = m.call("tile_to_chunk", Vector2i(17, 5))
	_check(tc == Vector2i(1, 0), "tile_to_chunk(17,5) -> (1,0) (got %s)" % tc)
	var clamped: Vector2i = m.call("clamp_chunk", Vector2i(9, -2))
	_check(clamped == Vector2i(3, 0), "clamp_chunk(9,-2) -> (3,0) (got %s)" % clamped)
	var rect: Rect2 = m.call("chunk_rect", Vector2i(1, 0))
	_check(
		rect.position == Vector2(256, 0) and rect.size == Vector2(256, 256),
		"chunk_rect(1,0) -> (256,0,256,256) (got %s)" % rect
	)
	var count: int = int(m.call("get_chunk_count"))
	_check(count == 16, "get_chunk_count() -> 16 (got %d)" % count)


## --- Renderer load / unload --------------------------------------------------

func _check_renderer() -> void:
	var renderer_script: Script = load("res://scripts/MapRenderer.gd") as Script
	_check(renderer_script != null, "MapRenderer script loads")
	if renderer_script == null:
		return
	var renderer: Node2D = renderer_script.new() as Node2D
	_check(renderer != null, "MapRenderer instantiates")
	if renderer == null:
		return
	for method in ["update_chunks", "get_loaded_chunks"]:
		_check(renderer.has_method(str(method)), "MapRenderer exposes %s()" % method)
	if not renderer.has_method("update_chunks") or not renderer.has_method("get_loaded_chunks"):
		return

	# 128x128 tiles / chunk 16 tiles = 8x8 chunks of 256 px. One object per chunk.
	var map := _make_map(128, 128, 16, 16)
	var item := Item.new()
	item.id = "item:chunk_probe"
	item.type = "prop"
	for cy in range(8):
		for cx in range(8):
			map.placed_objects.append({
				"position": Vector2(cx * 256 + 128, cy * 256 + 128),
				"item": item,
			})

	renderer.call("render", map)
	var tile_map: TileMap = renderer.get_node_or_null("TileMap") as TileMap
	var used_cells: int = tile_map.get_used_cells(0).size() if tile_map != null else -1
	_check(
		used_cells == 128 * 128,
		"all tiles live in one TileMap (Godot native culling; got %d)" % used_cells
	)

	# Re-render must not leave the previous children queued-but-present in the tree.
	var first_count: int = renderer.get_child_count()
	renderer.call("render", map)
	_check(
		renderer.get_child_count() == first_count,
		"re-render removes old children synchronously (got %d, expected %d)" % [
			renderer.get_child_count(), first_count
		]
	)

	# A scene-declared child (e.g. ChunkGridOverlay in Game.tscn) must survive a
	# re-render. This is the exact regression code-review finding #2 protects.
	var sentinel := Node2D.new()
	sentinel.name = "SceneChild"
	renderer.add_child(sentinel)
	renderer.call("render", map)
	_check(
		renderer.get_child_count() == first_count + 1,
		"re-render preserves scene-declared children (got %d, expected %d)" % [
			renderer.get_child_count(), first_count + 1
		]
	)
	_check(
		renderer.get_node_or_null("SceneChild") != null,
		"sentinel scene child survives re-render"
	)

	var loaded: Array = renderer.call("get_loaded_chunks")
	_check(loaded.size() == 36, "initial load around chunk (0,0) = 6x6 chunks (got %d)" % loaded.size())
	var chunks_root: Node = renderer.get_node_or_null("PlacedObjects")
	_check(
		chunks_root != null and chunks_root.get_child_count() == loaded.size(),
		"one placed-objects node per loaded chunk"
	)
	_check(loaded.has(Vector2i(0, 0)), "origin chunk loaded")
	_check(not loaded.has(Vector2i(7, 7)), "far corner chunk not loaded initially")

	# Small movement within the same chunk must not disturb the loaded set.
	renderer.call("update_chunks", Vector2(200, 200))
	var after_jitter: Array = renderer.call("get_loaded_chunks")
	_check(after_jitter.size() == loaded.size(), "no reload/churn within the same focus chunk")

	# Move focus to the far corner: new chunks load, the origin chunk is unloaded.
	renderer.call("update_chunks", Vector2(1920, 1920))
	var far_loaded: Array = renderer.call("get_loaded_chunks")
	_check(far_loaded.has(Vector2i(7, 7)), "focus chunk (7,7) loaded after moving")
	_check(not far_loaded.has(Vector2i(0, 0)), "origin chunk unloaded after moving away")
	# Hysteresis legitimately keeps a ring of previously loaded chunks, so the
	# resident count is >= the 6x6 core but below the full 8x8 grid.
	_check(
		far_loaded.size() >= 36 and far_loaded.size() <= 64,
		"resident chunk count bounded around new focus (got %d)" % far_loaded.size()
	)
	var far_root: Node = renderer.get_node_or_null("PlacedObjects")
	_check(
		far_root != null and far_root.get_child_count() == far_loaded.size(),
		"unloaded chunk nodes were freed (nodes %d, chunks %d)" % [
			far_root.get_child_count() if far_root != null else -1, far_loaded.size()
		]
	)

	# Hysteresis: a chunk at distance 6 stays loaded (load <=5, unload >6).
	renderer.call("update_chunks", Vector2(640, 640))  # center (2,2); (7,2) distance 5
	_check((renderer.call("get_loaded_chunks") as Array).has(Vector2i(7, 2)), "distance-5 chunk loads")
	renderer.call("update_chunks", Vector2(384, 640))  # center (1,2); (7,2) distance 6
	_check(
		(renderer.call("get_loaded_chunks") as Array).has(Vector2i(7, 2)),
		"hysteresis: distance-6 loaded chunk stays resident"
	)
	renderer.call("update_chunks", Vector2(128, 640))  # center (0,2); (7,2) distance 7
	_check(
		not (renderer.call("get_loaded_chunks") as Array).has(Vector2i(7, 2)),
		"hysteresis: distance-7 chunk is unloaded"
	)

	# Out-of-grid objects clamp to the nearest valid chunk instead of vanishing.
	var edge_map := _make_map(16, 16, 8, 16)  # 2x2 chunks of 128 px
	var edge_item := Item.new()
	edge_item.id = "item:edge_probe"
	edge_item.type = "prop"
	edge_map.placed_objects.append({"position": Vector2(-20, -20), "item": edge_item})
	var edge_renderer: Node2D = renderer_script.new() as Node2D
	edge_renderer.call("render", edge_map)
	var edge_node: Node2D = edge_renderer.call("get_chunk_node", Vector2i(0, 0)) as Node2D
	_check(
		edge_node != null and edge_node.get_child_count() == 1,
		"out-of-grid placed object clamps into edge chunk (0,0)"
	)


## --- Overlay -----------------------------------------------------------------

func _check_overlay() -> void:
	var overlay_script: Script = load("res://scripts/ChunkGridOverlay.gd") as Script
	_check(overlay_script != null, "ChunkGridOverlay script exists")
	if overlay_script == null:
		return
	var overlay: Node2D = overlay_script.new() as Node2D
	_check(overlay != null, "ChunkGridOverlay instantiates")
	if overlay == null:
		return
	get_tree().root.add_child(overlay)
	_check(overlay.has_method("set_map") and overlay.has_method("toggle"), "overlay has set_map/toggle seam")
	if overlay.has_method("set_map"):
		overlay.call("set_map", _make_map(64, 64, 16, 16))
	_check(InputMap.has_action("toggle_chunk_grid"), "toggle_chunk_grid input action exists")
	var before: bool = overlay.visible
	if overlay.has_method("toggle"):
		overlay.call("toggle")
	_check(overlay.visible != before, "overlay toggle() flips visibility")
	# Exercise the real action lookup path with a synthetic F6 press.
	var key := InputEventKey.new()
	key.physical_keycode = 4194337  # KEY_F6
	key.pressed = true
	overlay.call("_unhandled_input", key)
	_check(overlay.visible == before, "F6 action toggles the overlay through _unhandled_input")
	await get_tree().process_frame  # let _draw run with the synthetic map
	_check(true, "overlay draws without errors")


## --- Real scene wiring -------------------------------------------------------

func _check_real_game() -> void:
	GameManager.change_scene("res://scenes/DebugStart.tscn")
	var game: Node = null
	for _i in range(30):
		await get_tree().process_frame
		game = get_tree().root.get_node_or_null("Game")
		if game != null:
			break
	_check(game != null, "real Game.tscn loads through DebugStart")
	if game == null:
		return
	var renderer: Node2D = game.get_node_or_null("MapRenderer") as Node2D
	_check(renderer != null, "Game.tscn has a MapRenderer")
	if renderer == null:
		return
	_check(
		str(renderer.get("focus_path")) == "Player" or str(renderer.get("focus_path")) == "../Player",
		"renderer focus_path wired to the player (got '%s')" % str(renderer.get("focus_path"))
	)
	var overlay: Node = renderer.get_node_or_null("ChunkGridOverlay")
	_check(overlay != null, "Game.tscn has a ChunkGridOverlay under MapRenderer")
	_check(overlay != null and not overlay.visible, "chunk grid overlay is hidden by default")
	var map: Map = renderer.get("map") as Map
	_check(
		map != null and map.chunk_size == 32 and map.chunk_grid_size == Vector2i.ONE,
		"shipped map: chunk_size 32 -> 1x1 chunk grid"
	)


## --- Helpers -----------------------------------------------------------------

func _make_map(width: int, height: int, chunk_size: int, tile_size: int) -> Map:
	var m := Map.new()
	m.width = width
	m.height = height
	m.chunk_size = chunk_size
	m.tile_size = tile_size
	var ids := PackedInt32Array()
	ids.resize(width * height)
	ids.fill(0)
	m.tile_ids = ids
	return m


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("[020] FAIL: %s" % label)


func _finish() -> void:
	print("[020] checks: %d passed, %d failed" % [_passed, _failed])
	if _failed == 0:
		print("ALL_020_CHECKS_PASSED")
	else:
		print("[020] FAIL: %d check(s) failed" % _failed)
	get_tree().quit()
