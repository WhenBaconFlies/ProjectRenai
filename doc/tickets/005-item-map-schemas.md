# 005: Item + Map schemas

**What to build:** Define the `Item` and `Map` resource classes (`.tres`). `Item` carries an id, type, a `PackedScene` reference for instantiation, sprite/collider data, and properties for furniture/walls. `Map` carries tile data (grid of tile IDs), placed objects (list of {position, resource ref}), a spawn point, navigation mesh data, and a `chunk_size` field (tiles, default 32) with derived chunk grid dimensions (reserved for post-v1 chunk loading; harmless in v1).

**Blocked by:** 001 (Project scaffolding)

**Status:** done

- [x] `Item` resource class exists with `PackedScene` reference, sprite/collider data, and properties
- [x] `Map` resource class exists with tile data, placed objects, spawn point, and navmesh data
- [x] `Map` has a `chunk_size` field (tiles, default 32) with derived chunk grid dimensions
- [x] A `.tres` of each type can be created and saved in the editor without errors
- [x] Fields are typed and documented with comments