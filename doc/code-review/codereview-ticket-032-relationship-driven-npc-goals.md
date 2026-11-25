# Code Review: ticket/032-relationship-driven-npc-goals vs master

- **Branch:** `ticket/032-relationship-driven-npc-goals`
- **Base:** `master` (merge-base: `701077102a3e7857c782aaa404ec4b64b1af8e03`)
- **Changed files:** 10
- **Findings:** 6 (Critical: 0, High: 1, Medium: 3, Low: 2)
- **Reviewer:** fresh-context `code-reviewer` subagent; evidence audited with `evidence-validator` (verdict PASS — every finding cites `file:line` plus a diff hunk, test output or executed probe).

## Findings

### 1. [High][Bug] All-enemy fallback walks an NPC toward the player it avoids
- **Location:** `scripts/NpcAi.gd:113-127`, `scripts/NpcAi.gd:136-147`
- **Evidence:** Executed probe with a zero-hangout map, one player at `(321, 77)`, meter `affection = -25`: `goal=avoid:player dest=(321, 77)`. With no positive candidates, `use_base_weights` becomes true at `:136` and the player candidate is re-enabled at `:147` with its base weight of 1, so `scripts/Npc.gd:301` aims the nav agent at the enemy player. The 17-check harness only covers T11 (player enemy *with* rival hangouts).
- **Problem:** The last-resort fallback turns an "avoid" goal into actual movement toward the avoided player.
- **Recommendation:** Never append a `player:*` candidate when its effective weight is ≤ 0; if that leaves no candidate, return `no_goal` rather than selecting the enemy player. Add a headless check for an enemy player on a zero-hangout map.

### 2. [Medium][Bug] Hardcoded player id breaks configured player rosters
- **Location:** `scripts/NpcAi.gd:46`, `scripts/NpcAi.gd:250`
- **Evidence:** `Game.gd:1267-1269` resolves the player id from `TimeManager.player_character_id` (exported at `TimeManager.gd:81`), but `NpcAi` compares only to `PLAYER_ID = "player"`. Executed probes with player id `npc:hero` and a Lover meter returned `goal= dest=(0,0)` on a zero-hangout map and a random hangout with hangouts present, instead of the player's `(321, 77)`.
- **Problem:** A configured player id is treated as an ordinary NPC and uses the hash-derived hangout fallback, so seek/avoid toward that player silently stops working.
- **Recommendation:** Pass the live player id from `Game._wire_relationship_roster()` through `Npc.set_relationship_roster()` into `NpcAi.select_goal()` as an optional argument (default `"player"`), and match against it in `_relationship_weights_by_key()`.

### 3. [Medium][Bug] Opposing deltas at one hangout cancel friend-seeking
- **Location:** `scripts/NpcAi.gd:103`, `scripts/NpcAi.gd:108`, `scripts/NpcAi.gd:239-244`
- **Evidence:** Executed probe P4: a Friend (`+5`) and an Enemy (`-100`) both associated with `hangout_library` over 64 seeds produced `{"hangout:hangout_garden": 64}`; the library's summed delta of −95 clamps its effective weight to 0.
- **Problem:** An enemy at a shared hangout completely erases a friend's pull at the same place, even though seek and avoid are separate relationships.
- **Recommendation:** Accumulate seek and avoid deltas separately, then clamp only the combined weight at 0 when there is no positive seek contribution for that marker (a design choice — see ruling below).

### 4. [Medium][Architecture] T14 passes without exercising relationship weighting
- **Location:** `tests/NpcGoalsTest.gd:279-290`
- **Evidence:** `_stale_marker_fallback()` only asserts the goal is a valid hangout. A differential probe with an empty roster produced valid hangout goals in 300/300 samples, so T14 cannot fail when `_candidate_hangout()` stops contributing.
- **Problem:** The stale-marker fallback branch is not actually pinned by its test.
- **Recommendation:** Use `_goal_counts()` and assert the deterministic fallback marker (`hangouts[posmod(friend.instance_id.hash(), hangouts.size())]`) is chosen more often than in the empty-roster baseline.

### 5. [Low][Architecture] T17 is self-referential bookkeeping
- **Location:** `tests/NpcGoalsTest.gd:42`
- **Evidence:** `_check()` increments `_passed` only on success (`:46-52`), so T17's `_passed == EXPECTED_CHECKS - 1` is equivalent to "all previous checks passed" and observes no external state.
- **Problem:** A tautological check adds no failure detection.
- **Recommendation:** Remove it, or replace it with an observable assertion. (Deferred: every existing harness in `tests/` uses the same count-check convention.)

### 6. [Low][Architecture] Game's roster wiring has no direct harness coverage
- **Location:** `scripts/Game.gd:174`, `scripts/Game.gd:331`; `tests/NpcGoalsTest.gd:307`
- **Evidence:** A `tests/` search finds `set_relationship_roster` only in `NpcGoalsTest.gd:319`; T16 constructs a synthetic `Npc` directly, so fresh-start and restore wiring are verified by inspection only.
- **Problem:** A regression that drops either `_wire_relationship_roster()` call would not be caught by ticket 032's harness.
- **Recommendation:** Add a headless test that saves with a meter toward the player, loads `Game.tscn`, and asserts an NPC's goal uses the restored player instance's saved position.

## Evidence Audit

1. [SUPPORTED] Finding 1 — `NpcAi.gd:113-127/136-147`, executed probe output, and `Npc.gd:301`.
2. [SUPPORTED] Finding 2 — `NpcAi.gd:46/250`, `Game.gd:1267-1269`, `TimeManager.gd:81`, executed probes P2/P3.
3. [SUPPORTED] Finding 3 — `NpcAi.gd:103/108/239-244`, executed probe P4 (64/64 samples).
4. [SUPPORTED] Finding 4 — `NpcGoalsTest.gd:279-290`, 300-sample empty-roster differential.
5. [SUPPORTED] Finding 5 — `NpcGoalsTest.gd:42/46-52`.
6. [SUPPORTED] Finding 6 — `Game.gd:174/331`, `tests/` search result.

**Verdict: PASS** — unsupported claims: 0; no action required from the evidence audit.

## Declined to judge (reviewer)

- v1 empty-meter behavior: differential probe over 3 moods × 100 seeds reported `V1_DIFF samples=300 mismatches=0`; no regression.
- Roll bounds and determinism: no off-by-one or seed-collision evidence.
- Mutual-romance gate omission: explicitly user-approved in `doc/idea-v2-decisions.md`.
- Enemy hangout chosen by the all-negative fallback with hangouts present: explicitly user-approved and asserted by T9; finding 1 is limited to the player candidate, which has no separate safe destination.
- Weight constants and per-evaluation roster scans: tuning choices / no measured bottleneck.
