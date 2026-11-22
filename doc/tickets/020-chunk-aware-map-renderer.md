# 020: Chunk-aware map renderer + chunk grid overlay

**What to build:** Add a `chunk_size` (tiles) field to the `Map` schema with derived chunk grid dimensions. The map renderer loads and unloads chunks around the player (Godot native culling for tiles; manual node unload only beyond the far threshold). The map editor shows a chunk grid overlay so authors can see chunk boundaries. Chunks are a fixed tile grid with the same size/shape across maps (map dimensions vary).

**Blocked by:** 018 (Day-loop integration & acceptance verification), 008 (Map renderer)

**Status:** ready-for-agent

- [ ] `Map` schema has a `chunk_size` (tiles) field with derived chunk grid dimensions
- [ ] Chunk size is consistent across maps (fixed tile grid)
- [ ] Renderer loads chunks around the player and unloads far chunks
- [ ] Godot native culling is used for tiles; manual unload only beyond far threshold
- [ ] Map editor displays a chunk grid overlay
- [ ] A map with varying dimensions produces the correct chunk grid
- [ ] No pop-in or missing tiles during normal movement within the buffer zone