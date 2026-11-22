# 008: Map renderer

**What to build:** A renderer that takes a `Map` `.tres` and builds the world at runtime: tilemap from tile data, placed objects instantiated from their `Item` `PackedScene` references, and a baked navigation mesh for pathfinding. The spawn point is exposed for player/NPC placement.

**Blocked by:** 005 (Item + Map schemas), 007 (Minimal base content)

**Status:** ready-for-agent

- [ ] A `Map` `.tres` renders as a tilemap with placed objects visible
- [ ] Placed objects are instantiated from their `Item` `PackedScene` reference
- [ ] A navigation mesh is baked and available for `NavigationAgent2D`
- [ ] Spawn point is exposed for use by the spawner
- [ ] Renderer handles a map with no placed objects without errors