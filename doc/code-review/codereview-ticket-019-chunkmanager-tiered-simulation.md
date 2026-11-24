# Code Review: ticket 019 (uncommitted working tree) vs master

- **Branch:** master (changes uncommitted; base commit `590490d`)
- **Base:** master (merge-base: `590490d`)
- **Changed/new files in scope:** 11 (production + harness; `.planning/` excluded)
- **Findings:** 5 (Critical: 0, High: 1, Medium: 2, Low: 2)
- **Reviewer:** fresh `code-reviewer` subagent (read-only), plus `karpathy-guidelines` validation and `evidence-validator` audit

## Scope

Reviewed: `scripts/ChunkConfig.gd`, `scripts/ChunkManager.gd`, `scripts/NpcInstance.gd`, `scripts/Npc.gd`, `scripts/Game.gd`, `project.godot`, `tests/ChunkManagerBootstrap.tscn/.gd`, `tests/ChunkManagerTest.gd`, `tests/run_chunk_tests_019.ps1`, and `doc/idea-v1-decisions.md` (ticket-019 decisions only).

Verified clean by the reviewer: chunk coordinate math matches `Map.world_to_chunk()`; the hysteresis decision table matches the decision log; tick accumulation/reset is correct; `tier`/`coarse_position` remain unexported and excluded from `snapshot()`; `move_and_slide()` driven from `_process()` was empirically confirmed to use process delta (so tier-driven stepping does not change speed); 016/017/018/020 regressions pass.

## Findings

### 1. [High][Bug] Gapless promotion froze NPC simulation for the full 0.5 s

- **Location:** `scripts/ChunkManager.gd:242-253`, `scripts/ChunkManager.gd:340-343`; `tests/ChunkManagerTest.gd:215-232`
- **Evidence:** `_apply_tier()` created a `_promotions` entry on every promotion whenever `promotion_duration_sec > 0`; `tick_npcs()` then `continue`d for any id in `_promotions`. Both fine and coarse stepping mirror `global_position` into `instance.position`, so on an ordinary promotion `gap == 0` and the interpolation was a no-op that still froze AI, goal evaluation and travel timeouts for 0.5 s. The harness only exercised an artificially injected 500 px gap, and the shipped 1×1-chunk map never promotes, so all suites stayed green.
- **Problem:** On the intended post-v1 multi-chunk maps, every player-driven promotion stopped an NPC for half a second, and rapid boundary crossings repeated the freeze.
- **Recommendation:** Create the promotion entry only when `npc.global_position.distance_to(instance.position) > 0.01`.
- **Disposition:** Fixed in this session. Added RED/GREEN proof (removing the gap gate failed 2 checks; restoring it returned 60/60).

### 2. [Medium][Bug] `set_config()` did not reapply `hide_far_npcs` visibility

- **Location:** `scripts/ChunkManager.gd:62-66`, `scripts/ChunkManager.gd:237-238`, `scripts/ChunkManager.gd:257-258`
- **Evidence:** `set_config()` only cleared accumulators and called `_update_tiers()`; `_apply_tier()` returns early when the tier is unchanged, so the `npc.visible = false/true` assignment was never re-evaluated on a config swap. `ChunkConfig.gd:7-10` documents the seam for a future Options UI. The harness previously called `set_config()` twice with the same `hide_far_npcs = true`.
- **Problem:** Toggling `hide_far_npcs` at runtime left far NPCs in the old visibility state.
- **Recommendation:** After `_update_tiers()` in `set_config()`, iterate registered NPCs and set `visible = not (hide_far_npcs and tier == FAR)`.
- **Disposition:** Fixed in this session; regression checks added.

### 3. [Medium][Bug] Interaction guard promoted before rejecting an already-busy NPC

- **Location:** `scripts/Game.gd:424-433`
- **Evidence:** The `_initiation_busy.has(target.instance.instance_id)` check ran after `promote_for_interaction()`, which mutates tier, visibility, `coarse_position`, nav target, accumulator and emits `tier_changed`. A ticket-016 hold therefore caused those side effects and then returned without opening dialogue.
- **Problem:** Wasted and observable state perturbation for a character the interaction rejects.
- **Recommendation:** Move the `_initiation_busy` rejection above the promotion block.
- **Disposition:** Fixed in this session; real-scene regression check added.

### 4. [Low][Bug] `coarse_position` stale on the far-tier arrival tick

- **Location:** `scripts/Npc.gd:412-426`, `scripts/Npc.gd:454-471`; `tests/ChunkManagerTest.gd:290-300`
- **Evidence:** `_simulate_coarse()` mirrored `coarse_position` only on the moving branch; the early `_arrive()` return and `_arrive()` itself never touched it, breaking the "coarse mirrors authoritative while far" invariant for one tick.
- **Problem:** Any read of `coarse_position` immediately after a far NPC reached its goal saw a stale point.
- **Recommendation:** Mirror `instance.coarse_position = instance.position` in the arrival early-return path.
- **Disposition:** Fixed in this session; regression check added.

### 5. [Low][Bug] `unregister_npc()` un-hid a far NPC without resetting its tier

- **Location:** `scripts/ChunkManager.gd:153-161`
- **Evidence:** `unregister_npc()` unconditionally set `npc.visible = true` and returned the NPC to legacy per-frame simulation while `instance.tier` remained `FAR`; `_update_tiers()` no longer ran for it, so `is_interactable()` stayed false forever.
- **Problem:** Latent inconsistent state for the public unregister seam (no production call site today).
- **Recommendation:** On unregister, reset `instance.tier = TIER_CLOSE` and `coarse_position = position`.
- **Disposition:** Fixed in this session; regression check added.

## Evidence Audit

- All 5 findings cite `file:line` plus a code excerpt or a reproduced harness failure; none rely on opinion or vague phrasing.
- Verdict: **PASS** (0 unsupported, 0 mixed claims). No finding was dropped.

## Assessment

Ready to merge after the fixes above. No crash, security or data-loss defect found; save/load, hysteresis, tick rates and the interaction guard are all covered by observable assertions. Final verification: 019 harness **60/60** (`ALL_019_CHECKS_PASSED`), 018 **41/41**, 020 **58/58**, headless editor scan clean.

## Resolution

- Findings 1–5: fixed in `scripts/ChunkManager.gd`, `scripts/Npc.gd`, `scripts/Game.gd`; five new regression checks added to `tests/ChunkManagerTest.gd`.
- RED/GREEN proof for finding 1: temporarily removed the `gap > 0.01` gate → 58 passed / 2 failed (`gapless promotion ... does not start interpolation`, `NPC keeps simulating ...`); reverted → 60/60. An earlier RED proof for hysteresis (removing `+ buffer`) failed 2 checks and was reverted.
- Full 019/018/020 harnesses re-run after every fix; no source changes beyond the cited locations.
