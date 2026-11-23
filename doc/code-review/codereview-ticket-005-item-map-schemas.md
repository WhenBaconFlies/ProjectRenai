# Code Review: ticket/005-item-map-schemas vs master

- **Branch:** ticket/005-item-map-schemas
- **Base:** master (merge-base: d7ebafe)
- **Changed files:** 2 (scripts/Item.gd, scripts/Map.gd) plus ticket/doc updates
- **Findings:** 0 (Critical: 0, High: 0, Medium: 0, Low: 0)

## Findings

No findings.

## Verification

- Headless Godot 4.2.1 run: `Item.new()` and `Map.new()` instantiate without parse/runtime errors; `ResourceSaver.save` + `ResourceLoader.load` round-trips `id`, `blocks_movement`, `chunk_size`, and `placed_objects` (`chunk_grid=(2, 1)`, `placed=1`, exit code 0).
- Global script class cache registers both `Item` and `Map` as `Resource` subclasses, so they can be created from the editor's "New Resource" dialog.
- `Map.chunk_grid_width/height/size` derive correctly via ceil division (verified: 64x32 map with chunk_size 32 -> (2, 1)).
- Both scripts use `@export` typed fields with doc comments; trailing newlines are LF, matching repo convention.