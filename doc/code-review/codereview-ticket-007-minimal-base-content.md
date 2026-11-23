# Code Review: ticket/007-minimal-base-content vs master

- **Branch:** ticket/007-minimal-base-content
- **Base:** master (merge-base: c6ee0b3)
- **Changed files:** 16 (15 added resources + ticket status update; 5 modified in follow-up fix commit)
- **Findings:** 2 (Critical: 0, High: 0, Medium: 0, Low: 2) — 3 additional suggestions resolved during review

## Findings

### 1. [Low][Architecture] `trait_point_cost = 0` is ambiguous against nonzero trait costs
- **Location:** `resources/characters/char_alex.tres:31`, `resources/characters/char_sam.tres:31`
- **Evidence:** Alex's attached traits sum to +1 (studious +2, shy -1) and Sam's to +2 (outgoing +1, likes_sports +1), yet both templates declare `trait_point_cost = 0`. The schema documents this field as the "Trait point cost/budget associated with this character template", leaving 0 ambiguous between "no budget" and "zero spent".
- **Problem:** Downstream character-creation/budget logic (deferred surface feature) cannot distinguish a template with no constraint from one that spent zero points.
- **Recommendation:** Decide and document the semantics in `CharacterTemplate.gd` (budget vs. spent) and set values consistent with attached traits, or explicitly state that 0 means "no budget constraint".

### 2. [Low][Maintainability] Two authored traits are unreferenced by any character template
- **Location:** `resources/traits/trait_athletic.tres`, `resources/traits/trait_dislikes_noise.tres`
- **Evidence:** Only `trait_studious`, `trait_shy`, `trait_outgoing`, and `trait_likes_sports` appear in `traits = [...]` arrays in `char_alex.tres` / `char_sam.tres`.
- **Problem:** Athletic and dislikes_noise exist to satisfy category coverage but are not exercised by the two characters, so they are not validated by the day-loop seam until a third character or mod uses them.
- **Recommendation:** Either add a third character template that uses them, or document them in a README/mod sample note as available-for-modding traits. Acceptable for minimal content.

## Resolved during review (not in final diff's open items)

- **Navmesh routed through walls/furniture** (`resources/maps/map_school.tres`): rebuilt as interior-only walkable region with holes for the three furniture cells; `NavigationAgent2D` paths no longer cross the wall border or desks/bench.
- **Spawn point on a tile corner** (`resources/maps/map_school.tres`): moved from `Vector2(16, 16)` to `Vector2(24, 24)` (cell center), clear of adjacent wall collision.
- **Inconsistent trait tags** (`resources/traits/*.tres`): added tags to studious, athletic, outgoing, and shy for parity with likes_sports/dislikes_noise.

## Verification

- All 14 `.tres` files parse and round-trip via `ResourceLoader.load` / `ResourceSaver.save` (headless Godot 4.2.1), including the modified map and traits.
- `load_steps` counts match declared ext/sub resources; all `ExtResource`/`SubResource` IDs resolve.
- All property keys conform to the 004–006 schemas; only the expected `script` pseudo-property is extra.
- Map tile grid length = 80 (= 10×8); 35 placed objects (32 walls + 2 desks + 1 bench); all positions within 160×128 px bounds; no duplicate wall cells.
- Trait categories present: skill (athletic, studious), interest (likes_sports), dislike (dislikes_noise), personality (outgoing, shy) — satisfies ticket criteria.
- Navmesh now yields 10 polygons avoiding walls and furniture; spawn at cell center.
- Trailing newline present (LF); no CRLF.