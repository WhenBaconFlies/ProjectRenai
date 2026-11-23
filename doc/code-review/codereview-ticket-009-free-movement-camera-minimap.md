# Code Review: ticket/009-free-movement-camera-minimap vs master

- **Branch:** ticket/009-free-movement-camera-minimap
- **Base:** master (merge-base: e60e7a2)
- **Changed files:** 8 (scripts/Player.gd, scripts/FollowCamera.gd, scripts/Minimap.gd, scenes/Game.tscn, project.godot, resources/maps/map_school.tres, doc/tickets/009-free-movement-camera-minimap.md, doc/idea-v1-decisions.md)
- **Findings:** 6 (Critical: 0, High: 0, Medium: 2, Low: 4)

## Findings

### 1. [Medium][Bug] Input-action fallback returns on the first existing action, leaving missing actions unbound
- **Location:** `scripts/Player.gd:93-96`
- **Evidence:** `for action in [...]: if InputMap.has_action(action): return; InputMap.add_action(action, 0.5)`. The `return` is inside the loop. If `move_left` exists but `move_down` does not, the function returns on iteration 1 and `move_down` is never added; if only `move_left` is missing, it is created at line 96 but iteration 2 returns before the event registrations at lines 98-113 run, leaving `move_left` with zero events. Normal runs are unaffected because `project.godot:27-61` defines all four actions.
- **Problem:** The defensive fallback fails in exactly the partial-configuration case it exists to handle, silently disabling some movement directions.
- **Recommendation:** Gather all missing actions first, add every one of them, then register the key/axis/button events for each newly created action; remove the early `return`.

### 2. [Medium][Architecture] Camera limits are cached once and not recomputed if the rendered map changes
- **Location:** `scripts/FollowCamera.gd:48-62`, `scripts/FollowCamera.gd:92-93`
- **Evidence:** `_map_pixel_size` is assigned only in `_resolve_nodes()` (lines 58-61), called once via `call_deferred` from `_ready()` (line 44). `_on_viewport_resized()` re-applies only the cached size. `scripts/MapRenderer.gd:36-53` explicitly allows repeated `render()` calls ("Safe to call repeatedly"), and `scripts/Minimap.gd:69-73` detects `map != _last_map` every frame. After a map swap the camera clamps to the old map while the minimap draws the new one.
- **Problem:** A runtime map swap leaves camera bounds stale, pinning the view to a wrong region or showing empty space.
- **Recommendation:** Cache and compare `_renderer.map` in `_process()` (or consume a `rendered` signal from MapRenderer) and recompute `_map_pixel_size` + `_apply_limits()` whenever the map resource changes.

### 3. [Low][Bug] Minimap ignores authored collider shape/offset when drawing solid objects
- **Location:** `scripts/Minimap.gd:124-130`
- **Evidence:** The drawn rect uses `pos - Vector2(tile_size*0.5, tile_size*0.5)` with size `Vector2(tile_size*scale, tile_size*scale)`, while `scripts/MapRenderer.gd:183-190` builds the physics collider from `item.collider_shape` and `item.collider_offset` (tile-size rectangle fallback). Base content has `collider_shape = null` / `collider_offset = 0`, so current visuals are correct; any modded item with a custom collider will be misrepresented.
- **Problem:** The minimap can show solid areas that do not match actual collision, producing misleading navigation data.
- **Recommendation:** Derive the drawn rect from `item.collider_shape.get_rect()` plus `item.collider_offset`, falling back to the tile-size rect used by MapRenderer.

### 4. [Low][Bug] Odd map extent can invert the camera's clamp range
- **Location:** `scripts/FollowCamera.gd:78-81`, `scripts/FollowCamera.gd:86-89`
- **Evidence:** When `map_extent <= half_view * 2`, `_axis_limit()` returns `int(round(extent * 0.5))`; for `extent = 161` this is `81`, and `limit_right = 161 - 81 = 80`, so `limit_left > limit_right`. Reached when the zoomed view is larger than the map (low `zoom_level`). Default extent is `10 * 16 = 160` (`resources/maps/map_school.tres:18-20`), so not triggered today.
- **Problem:** An inverted limit range can produce undefined camera clamping on maps with odd pixel extents at low zoom.
- **Recommendation:** Pin the center with `limit_left = int(floor(extent * 0.5))` and compute `limit_right = extent - limit_left` (or clamp `limit_right = maxf(limit_right, limit_left)`).

### 5. [Low][Architecture] Exported `body_radius` only changes the visual, not the physics collider
- **Location:** `scripts/Player.gd:36`, `scripts/Player.gd:82-84`, `scenes/Game.tscn:9-10`, `scenes/Game.tscn:23-24`
- **Evidence:** `body_radius` drives the three `draw_circle` calls, but the collider is a hardcoded `CircleShape2D radius = 6.0` sub-resource in Game.tscn. Editing the exported value in the inspector desynchronizes drawn body from the shape used by `move_and_slide()` (`scripts/Player.gd:77`).
- **Problem:** A single authoritative value is split across code and scene data, so inspector tuning silently breaks collision/visual alignment.
- **Recommendation:** In `_ready()`, set the child `CollisionShape2D.shape` radius from `body_radius`, or remove the export and define the radius once as a constant.

### 6. [Low][Architecture] Player spawn uses a hardcoded sibling NodePath while camera/minimap use exported paths
- **Location:** `scripts/Player.gd:53`
- **Evidence:** `_snap_to_spawn()` calls `get_node_or_null("../MapRenderer")`, while `scripts/FollowCamera.gd:16,19` and `scripts/Minimap.gd:18,21` expose `@export var ...path` wired in `scenes/Game.tscn:28-29,48-49`. If the node moves, the fallback keeps the scene position `Vector2(24, 24)` (`scenes/Game.tscn:20`) — the old bad spawn recorded in `doc/idea-v1-decisions.md` — with only a `push_warning`.
- **Problem:** Inconsistent wiring convention makes the spawn lookup brittle and can silently reintroduce a spawn-inside-collider bug on scene refactors.
- **Recommendation:** Add `@export var map_renderer_path: NodePath = ^"../MapRenderer"` to Player, resolve through it, and wire it in Game.tscn like the other two scripts.

## Verification

- Headless Godot 4.2.1 (`D:\Godot\Godot_v4.2.1-stable_win64_console.exe`) integration script (temporary, removed after use): `ALL_009_CHECKS_PASSED`, exit code 0. Asserted: all four nodes load; input actions exist; player spawns at `(56, 24)`; camera zoom `8`, smoothing on, view-aware limits `L4 T4 R156 B124` under the headless 64x64 viewport; minimap draws and redraws on movement (30 -> 45 draws); player moves right under input (`56.0 -> 86.7`); player stops at `x=130.0` against the right wall; camera follows player and its screen center clamps at the map edge (`151.9` for a target of `220`).
- Headless launch-path script: `LAUNCH_PATH_OK`, exit code 0 — `DebugStart.tscn` loads `Game.tscn` with Player and Minimap present.
- Input map inspection: `move_left => key:65(A), key:4194319(Left), axis:0/-1, btn:13`; `move_right => key:68(D), key:4194321(Right), axis:0/1, btn:14`; `move_up => key:87(W), key:4194320(Up), axis:1/-1, btn:11`; `move_down => key:83(S), key:4194322(Down), axis:1/1, btn:12`.
- `D:\Godot` exists but is not on `PATH`; the reviewer could not reproduce the runs above.
- **Not verified:** the "no jitter or stutter at 60 fps" criterion needs a visual check in a windowed run (headless tests cannot measure frame pacing/smoothing feel).
