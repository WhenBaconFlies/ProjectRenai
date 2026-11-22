# 005: Item + Map schemas

**What to build:** Define the `Item` and `Map` resource classes (`.tres`). `Item` carries an id, type, a `PackedScene` reference for instantiation, sprite/collider data, and properties for furniture/walls. `Map` carries tile data (grid of tile IDs), placed objects (list of {position, resource ref}), a spawn point, and navigation mesh data.

**Blocked by:** 001 (Project scaffolding)

**Status:** ready-for-agent

- [ ] `Item` resource class exists with `PackedScene` reference, sprite/collider data, and properties
- [ ] `Map` resource class exists with tile data, placed objects, spawn point, and navmesh data
- [ ] A `.tres` of each type can be created and saved in the editor without errors
- [ ] Fields are typed and documented with comments