# 020: Chunk-aware map renderer + chunk grid overlay

**What to build:** Add a `chunk_size` (tiles) field to the `Map` schema with derived chunk grid dimensions. The map renderer loads and unloads chunks around the player (Godot native culling for tiles; manual node unload only beyond the far threshold). The map editor shows a chunk grid overlay so authors can see chunk boundaries. Chunks are a fixed tile grid with the same size/shape across maps (map dimensions vary).

**Blocked by:** 018 (Day-loop integration & acceptance verification), 008 (Map renderer)

**Status:** done

- [x] `Map` schema has a `chunk_size` (tiles) field with derived chunk grid dimensions
- [x] Chunk size is consistent across maps (fixed tile grid)
- [x] Renderer loads chunks around the player and unloads far chunks
- [x] Godot native culling is used for tiles; manual unload only beyond far threshold
- [x] Map editor displays a chunk grid overlay
- [x] A map with varying dimensions produces the correct chunk grid
- [x] No pop-in or missing tiles during normal movement within the buffer zone

## Notes from ticket 008
- `MapRenderer.render()` currently frees previous children with `queue_free()` and then builds replacements in the same call, so a re-render within one frame can briefly leave duplicate nodes in the tree (low finding in `doc/code-review/codereview-ticket-008-map-renderer.md`). When implementing chunk load/unload (which re-renders), prefer removing children from the tree synchronously before queuing them for deletion, e.g. `remove_child(child); child.queue_free()`.

## Implementation notes
- v1 has no map editor (deferred surface feature). Per user decision in `doc/idea-v1-decisions.md`, the overlay criterion is met by a reusable `ChunkGridOverlay` component under `MapRenderer`, hidden by default and toggled with F6; a future editor can reuse it by assigning `map`.
- Renderer-owned `load_radius_chunks = 5` / `unload_radius_chunks = 6` (Chebyshev chunk distance, one chunk of hysteresis). These are a seam for ticket 019's future `ChunkManager`, which is blocked by this ticket.
- Ticket 008's tile loop set cells with Godot 4.2's default atlas coords `(-1,-1)`, which creates no cells; explicit `Vector2i(tid, 0)` atlas coords were added so tiles (and therefore the floor) actually render.

## Verification
Persistent headless harness: `tests/run_chunk_tests.ps1` (boots `tests/ChunkRendererBootstrap.tscn` → real `DebugStart.tscn` → `Game.tscn`). 58/58 checks pass with `ALL_020_CHECKS_PASSED`. RED proof 1: before implementation, 12 checks failed (missing Map helpers, renderer seams, overlay, scene wiring); all passed after implementation. RED proof 2: temporarily making `render()` remove every child failed the overlay-survival checks (and the real-game overlay checks), then reverting restored green — proving the harness catches the scene-child regression. The ticket-018 regression suite still passes 41/41; headless editor scan is clean. Review report: `doc/code-review/codereview-ticket-020-chunk-aware-map-renderer.md` (4 Minor findings; 2 fixed, 2 deferred).
