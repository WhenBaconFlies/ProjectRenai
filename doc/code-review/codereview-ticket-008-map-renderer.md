# Code Review: ticket/008-map-renderer vs master

- **Branch:** ticket/008-map-renderer
- **Base:** master (merge-base: c86fad8)
- **Changed files:** 4 (scripts/MapRenderer.gd, scenes/Game.tscn, doc/tickets/008-map-renderer.md, doc/idea-v1-decisions.md)
- **Findings:** 1 (Critical: 0, High: 0, Medium: 0, Low: 1)

## Findings

### 1. [Low][Architecture] `render()` frees previous children with `queue_free()` but immediately builds replacements
- **Location:** `scripts/MapRenderer.gd:28-36`
- **Evidence:** `for child in get_children(): child.queue_free()` is followed in the same call by `tile_map = TileMap.new(); add_child(tile_map)` etc. `queue_free()` defers deletion to end of frame, so a second `render()` in the same frame leaves the old `TileMap`/`PlacedObjects`/`NavigationRegion2D` in the tree alongside the new ones until the frame ends.
- **Problem:** Re-rendering within a single frame (e.g. rapid map swaps) can briefly leave duplicate render nodes in the tree; references are overwritten, so only the newest is tracked.
- **Recommendation:** If re-rendering must be safe within one frame, remove children synchronously (`remove_child` + `free()`) or guard `render()` against re-entry until the frame ends. For v1's one-shot load path this is not exercised; leaving as-is is acceptable.

## Verification

- Headless Godot 4.2.1 run of `res://scenes/Game.tscn` via `tools_test.gd`: `GAME_LOADED_OK`, node tree contains `TileMap`, 35 placed-object nodes under `PlacedObjects` (32 walls + 2 desks + 1 bench), `NavigationRegion2D`, and `Marker2D SpawnPoint`; exit code 0, no parse/runtime errors.
- Empty-map case via `tools_test2.gd`: `EMPTY_MAP_OK`, `placed_count=0`, `spawn=(24, 24)`, `tilemap=true`, `nav=true`, no errors.
- `map_school.tres` (tile_set null) renders via the generated fallback tileset without errors.