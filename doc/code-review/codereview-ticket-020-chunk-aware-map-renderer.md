# Code Review: ticket 020 (uncommitted working tree) vs master

- **Branch:** master (changes uncommitted; base commit `ae933c1`)
- **Base:** master (merge-base: `ae933c1`)
- **Changed files in scope:** 9 (production + harness; pre-existing `.tres` edits and docs excluded)
- **Findings:** 4 (Critical: 0, High: 0, Medium: 0, Low/Minor: 4)
- **Reviewer:** fresh `code-reviewer` subagent (read-only), plus evidence audit

## Scope

Reviewed: `scripts/Map.gd`, `scripts/MapRenderer.gd`, `scripts/ChunkGridOverlay.gd`, `project.godot`, `scenes/Game.tscn`, `tests/ChunkRendererTest.gd`, `tests/ChunkRendererBootstrap.gd`, `tests/ChunkRendererBootstrap.tscn`, `tests/run_chunk_tests.ps1`.

Excluded: the developer's pre-existing uncommitted `resources/items/*.tres` and `resources/maps/map_school.tres` re-saves; documentation files (`doc/idea-v1-decisions.md`, `doc/tickets/020-*.md`).

## Findings

### 1. [Minor][Architecture] Chunk recomputation is O(total chunks) and O(all placed objects) per crossing

- **Location:** `scripts/MapRenderer.gd:160-168`, `scripts/MapRenderer.gd:175-183`
- **Evidence:** `update_chunks()` loops the full grid (`for cy in range(map.chunk_grid_height): for cx in range(map.chunk_grid_width)`); `_load_chunk()` rescans every entry of `map.placed_objects` for each chunk it loads. The recorded decision at `doc/idea-v1-decisions.md:342` claims one division per frame — true only in the steady state (`:153-156`, `:221-227`), not on a crossing frame.
- **Problem:** On the stated very-large-map target (`doc/idea-v1-spec.md:107`) a 1000×1000 chunk grid costs ~1M iterations per crossing, and every newly loaded chunk rescans all objects.
- **Recommendation:** Iterate only the `(2*load_radius+1)²` window around `center` for loads and `_loaded_chunks.keys()` for unloads; pre-bucket `map.placed_objects` by chunk once in `render()` so `_load_chunk()` is O(objects-in-chunk).
- **Disposition:** Deferred. v1 ships a 1×1 chunk map and 4 NPCs; the steady-state cost is already one division. This is a scalability optimisation for the post-v1 ChunkManager (ticket 019), not a correctness or v1-performance defect. Cost if wrong: a future very-large map would cross chunks with a visible hitch until this is applied.

### 2. [Minor][Testing] Overlay-survival regression is not covered by the harness

- **Location:** `tests/ChunkRendererTest.gd:119-127`, `tests/ChunkRendererTest.gd:210-236`
- **Evidence:** The re-render check uses a standalone renderer with no scene-declared children, so it only verifies child-count preservation. `_check_real_game()` confirms the overlay exists but never calls `render()` again. A regression that removes all children (instead of `_generated_children`) would still pass all 55 checks while deleting the overlay in the real game — the exact failure recorded at `doc/idea-v1-decisions.md:347`.
- **Problem:** The allow-list that protects scene children is the least-tested part of the change.
- **Recommendation:** Add a sentinel `Node2D` child (or real overlay) to a fresh renderer, call `render()` twice, and assert the sentinel is still a child. Optionally assert an out-of-grid placed object lands in the edge chunk.
- **Disposition:** Fixed in this session (see Resolution).

### 3. [Minor][Documentation] `tile_to_chunk()` doc comment claims clamping it does not perform

- **Location:** `scripts/Map.gd:154-155`
- **Evidence:** Comment says "then clamp at the grid edge"; the body (`:156-162`) only performs `floori(...)` with no `clampi` and no `clamp_chunk()` call.
- **Problem:** A caller could assume the result is always in `[0, grid-1]` and index without clamping.
- **Recommendation:** Remove the clamping claim (keep the helper pure); `clamp_chunk()` is the real clamping seam.
- **Disposition:** Fixed in this session (see Resolution).

### 4. [Minor][Testing] Harness leaks nodes at process exit

- **Location:** `tests/ChunkRendererTest.gd:90`, `tests/ChunkRendererTest.gd:189`
- **Evidence:** The synthetic renderer and the overlay added to `/root` are never freed. Run log ends with `ERROR: 1 RID allocations of type '9NavRegion' were leaked at exit`, `ERROR: 173 RID allocations of type 'N18RendererCanvasCull4ItemE' were leaked at exit`, `WARNING: ObjectDB instances leaked at exit`, `ERROR: Resources still in use at exit`.
- **Problem:** Noisy CI output that can mask a genuine production leak.
- **Recommendation:** Keep refs to the synthetic renderer/overlay as members and `free()` them in `_finish()` before `get_tree().quit()`.
- **Disposition:** Deferred. The same shutdown noise is present in ticket 018's baseline harness (`tests/run_integration.ps1`), so it is an accepted repo-wide headless-Godot artifact rather than a regression introduced by ticket 020. Cost if wrong: a future real leak in this harness would be harder to spot in the log.

## Declined to judge (rulings)

- **Authored multi-source TileSet atlas mapping** (`scripts/MapRenderer.gd:109-122`) — explicitly accepted as a v1 limitation in `doc/idea-v1-decisions.md:346`; no authored TileSet ships in scope. Cost if wrong: a future authored multi-source TileSet needs an explicit id→atlas mapping.
- **NavigationServer "map query failed before first synchronization" errors** — pre-existing ticket-013 NPC behavior, reproduced in ticket 018's baseline log; not introduced by these files. Cost if wrong: a real nav regression could be dismissed as noise (tracked by the existing harness).
- **`MapRenderer` under a non-origin parent transform** — `_process` uses `focus.global_position` while `_load_chunk` uses object-local positions; they diverge only if the renderer is moved under a transformed parent. `Game.tscn` keeps it at the origin and this is outside stated v1 scope. Cost if wrong: chunk assignment would be offset if the scene is restructured.
- **Overlay visual aesthetics (label size, line colour)** — subjective and already configurable via exports (`scripts/ChunkGridOverlay.gd:18-24`). Cost if wrong: easy visual tweak later.

## Assessment

**Ready to merge:** Yes, with the two cheap Minor fixes applied (findings 2 and 3). No correctness blocker, no security concern; the harness verifies real behavior (55/55, `ALL_020_CHECKS_PASSED`) and the ticket-018 regression suite is still 41/41.

## Resolution

- Finding 3: removed the incorrect clamping sentence from the `tile_to_chunk()` doc comment; TDD verification via the full 020 harness.
- Finding 2: added an overlay-survival regression check with a RED proof (temporarily made `render()` remove every child → the new check failed → reverted → passed). Full 020 harness re-run after both fixes.
- Findings 1 and 4: deferred with the dispositions above; no source changes.
