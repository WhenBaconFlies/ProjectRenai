# Relationship-driven NPC goals (ticket 032) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `NpcAi.relationship_candidates()` into seeded free-time goal selection so directed meters make NPCs seek friends/love interests (including the player) and avoid enemies through the existing hangout markers, while v1 interest/mood behavior stays unchanged.

**Architecture:** Pure meter classification in `NpcAi` reuses `DialogueResolver`'s numeric thresholds; the resulting weights are folded into the same seeded weighted-hangout loop v1 already uses. Enemy weights are heavily negative (a hangout is skipped while any positive candidate exists; if none exists, the base weights are restored so selection never dead-ends). `Npc.gd` receives a live roster from `Game.gd`; a marker-based headless harness proves seek/avoid with authored meters.

**Tech Stack:** Godot 4.2 / GDScript; PowerShell marker-based harness (`ALL_032_CHECKS_PASSED`); isolated worktree branch `ticket/032-relationship-driven-npc-goals`.

**Spec:** `doc/tickets/032-relationship-driven-npc-goals.md`; `doc/idea-v2-spec.md` (AC 12); `doc/idea-v2-decisions.md` (Ticket 032 decisions — user-approved mappings below).

## Global Constraints

- GDScript only; no C# (v2 decision).
- `NpcAi` stays pure: no scene-tree or autoload access; it may reference `DialogueResolver` constants only.
- No new authored `.tres` content; hangout association comes from the candidate's `current_goal` with a deterministic fallback over existing markers.
- Reuse `DialogueResolver` thresholds verbatim: Friend familiarity ≥ 20 and affection ≥ 20; Lover ≥ 60/≥ 60; Enemy affection ≤ -20. The mutual-romance template gate is not applied here (the pure hook has no template input).
- The player is a relationship candidate: positive meters seek `player.position`; negative meters avoid it.
- Enemy handling uses a negative weight, not exclusion: when nothing else qualifies, the enemy-linked destination may still be chosen via the base-weight fallback.
- v1 seeded behavior is unchanged when meters are empty; `select_goal()` keeps its existing 5-argument call shape via a default `all_instances: Array = []`.
- Marker-based pass/fail; Godot console exe exit code is logged but not authoritative.
- No push to GitHub without final user approval; after an approved push, mark issue #32 complete.

## Review Focus

1. Empty, malformed or missing meters and null roster entries must not crash — T1/T14/T15 pin this.
2. A candidate's stale/missing hangout marker, a map with no hangouts, and an all-enemy map must still return a usable no-crash result — T9/T10/T14 pin this.
3. Negative weights must never produce a negative total, an out-of-range roll, or a dead-end when every candidate is an enemy — T8/T9 pin this.
4. With empty meters, the v1 interest/mood distribution and seeded determinism must be byte-for-byte unchanged — T6/T12/T13 pin this.
5. Restoring a save replaces the player instance; a stale roster must not silently disable player seek/avoid after load — T16 plus Game wiring pins this.

---

### Task 1: Headless harness with all RED checks

**Files:**
- Create: `tests/NpcGoalsBootstrap.gd`, `tests/NpcGoalsBootstrap.tscn`, `tests/NpcGoalsTest.gd`, `tests/run_npc_goals_tests.ps1`

**Interfaces:**
- Consumes: `NpcAi.relationship_candidates(instance: NpcInstance, all_instances: Array) -> Array`; `NpcAi.select_goal(instance, template, map, seed_value, eval_count, all_instances: Array = []) -> Dictionary`; `NpcInstance.meters`, `current_goal`, `position`; `Map.get_hangout_marker_names()`, `Map.get_marker()`; `Npc.setup()`, `Npc.set_relationship_roster()`, `Npc.set_ai_enabled()`.
- Produces: marker `ALL_032_CHECKS_PASSED`, check prefix `[032]`, `EXPECTED_CHECKS = 17`.

- [ ] **Step 1: Write bootstrap + launcher** following `tests/ConversationHelperBootstrap.*` and `tests/run_conversation_helper_tests.ps1`, with log `renai-npc-goals-032.log` and success tokens `ALL_032_CHECKS_PASSED` + `NPC_GOALS_032_OK`.
- [ ] **Step 2: Write `NpcGoalsTest.gd` with these 16 behaviors plus a final count check (T17).** Helpers construct `NpcInstance`, `CharacterTemplate`, `Map` directly (no scene tree); a 4-marker map mirrors `map_school.tres`: `hangout_cafeteria`, `hangout_courtyard`, `hangout_garden`, `hangout_library`.
  - T1: `relationship_candidates(null, [])` and `relationship_candidates(instance, [])` return empty arrays.
  - T2: meter `{"familiarity": 25, "affection": 25}` toward `npc:friend` yields exactly one candidate with `relationship == "Friend"` and `weight == 5`.
  - T3: `{"familiarity": 65, "affection": 65}` yields `"Lover"`, `weight == 8`.
  - T4: `{"familiarity": 0, "affection": -25}` yields `"Enemy"`, `weight == -100`.
  - T5: meters for Stranger `{"familiarity": 5, "affection": 5}` and Acquaintance `{"familiarity": 25, "affection": 5}`, a malformed non-Dictionary meter, and a null roster entry yield no candidate and no crash.
  - T6: with a Friend candidate whose `current_goal == "hangout:hangout_library"`, 64 fixed seeds choose `hangout:hangout_library` more often than the same 64 seeds with no roster, and more often than any other marker.
  - T7: a Lover candidate at `hangout:hangout_garden` is chosen more often than the no-roster baseline for the same seeds.
  - T8: an Enemy candidate at `hangout:hangout_library` is never chosen across 64 seeds while the other three markers exist.
  - T9: a single-marker map with an Enemy candidate still returns that marker's hangout goal (fallback, no dead-end, no out-of-range roll).
  - T10: with a zero-hangout map and a Lover meter toward `player`, `select_goal()` returns `goal == "seek:player"` and `destination == player.position` for every tested seed.
  - T11: with an Enemy meter toward `player` and three normal hangouts, `"avoid:player"`/`player.position` is never chosen across 64 seeds.
  - T12: with an empty roster, a low-mood (`20`) NPC chooses a `quiet`-tagged hangout more often across 64 seeds than a high-mood (`80`) NPC; this matches v1 weighting.
  - T13: same instance/template/map/seed/eval/roster returns identical `goal` and `destination` on two calls.
  - T14: a Friend candidate whose `current_goal` names a missing marker still produces a valid hangout goal from the remaining markers; no crash, no empty goal.
  - T15: a roster containing `null`, non-`NpcInstance` values, self, and a duplicate id does not crash or create a self-candidate.
  - T16: build a real `Npc` node, `setup(instance)`, `set_relationship_roster([friend])`, `set_ai_enabled(true, single_marker_map, 7)`; the node's instance ends with the friend's hangout goal and destination.
  - T17: `_check(_passed == EXPECTED_CHECKS - 1, "T17: all expected 032 checks executed")`, then print `ALL_032_CHECKS_PASSED` only when `_failed == 0`.
- [ ] **Step 3: Run `powershell -ExecutionPolicy Bypass -File .\tests\run_npc_goals_tests.ps1`.** Expected: `NPC_GOALS_032_FAILED`, no `ALL_032_CHECKS_PASSED`, `[032] FAIL` lines for unimplemented seams. Record this RED output in the ledger.
- [ ] **Step 4: Commit** `tests/NpcGoals*` + `tests/run_npc_goals_tests.ps1` with message `test(032): add relationship-driven goal harness (RED)`.

### Task 2: Pure relationship weighting in NpcAi

**Files:**
- Modify: `scripts/NpcAi.gd`

**Interfaces:**
- Consumes: `DialogueResolver.REL_FRIEND_FAM/AFF`, `REL_LOVER_FAM/AFF`, `REL_ENEMY_AFF`; `NpcInstance.meters`, `current_goal`, `position`, `instance_id`.
- Produces: `relationship_candidates(instance, all_instances) -> Array` of `{id, instance, relationship, weight, familiarity, affection}`; `select_goal(..., all_instances: Array = [])`; constants `SEEK_FRIEND_WEIGHT = 5`, `SEEK_LOVER_WEIGHT = 8`, `AVOID_ENEMY_WEIGHT = -100`, `PLAYER_ID = "player"`.

- [ ] **Step 1: Implement `relationship_candidates()`.** Defensive iteration (skip null/non-`NpcInstance`/self/duplicate id), non-Dictionary meters treated as empty, thresholds in Lover → Enemy → Friend order exactly as `DialogueResolver.relationship_type()` orders them. No template lookup.
- [ ] **Step 2: Extend `select_goal()` with the optional 6th parameter and fold candidates into the existing weighted loop.** Candidate-to-destination rule: `player` id → `player.position` with `seek:<id>`/`avoid:<id>` goal and base weight 1; NPC → the hangout in `current_goal` if it still exists on the map, otherwise `hangouts[posmod(target.instance_id.hash(), hangouts.size())]`; add the candidate weight to that hangout's v1 base weight. Pick over strictly positive weights; if the total is ≤ 0, roll over base weights instead. Keep the existing RNG seed and candidate order for empty rosters.
- [ ] **Step 3: Run the harness.** Expected: T1–T15 and T17 pass; T16 still fails (roster not wired). Read the output.
- [ ] **Step 4: Commit** `scripts/NpcAi.gd` with message `feat(032): weight free-time goals with directed relationship meters`.

### Task 3: Live roster wiring in Npc + Game

**Files:**
- Modify: `scripts/Npc.gd`, `scripts/Game.gd`

**Interfaces:**
- Consumes: `NpcAi.select_goal(..., _relationship_roster)`; `Game._instances_by_id` (all NPC instances plus player instance).
- Produces: `Npc.set_relationship_roster(instances: Array) -> void`; `Game._wire_relationship_roster() -> void` called after `_setup_player_instance()` and again at the end of `_restore_from_save()`.

- [ ] **Step 1: Add `_relationship_roster` to `Npc.gd`, `set_relationship_roster()`, and pass it as the 6th `select_goal()` argument in `evaluate_goal()`.** Default empty array keeps direct-construction harnesses working.
- [ ] **Step 2: Add `Game._wire_relationship_roster()`** that snapshots `_instances_by_id.values()` and assigns it to every spawned NPC; call it in `_ready()` immediately after `_setup_player_instance()` and at the end of `_restore_from_save()` so a restored player instance replaces the stale one.
- [ ] **Step 3: Run the harness.** Expected: all 17 checks pass and `NPC_GOALS_032_OK` prints. Read the output.
- [ ] **Step 4: Run the v1 day-loop regression** (`tests/run_integration.ps1`) and the 013-era chunk harnesses (`tests/run_chunk_tests.ps1`, `tests/run_chunk_tests_019.ps1`). Expected: their existing markers still print with no new `FAIL` lines.
- [ ] **Step 5: Commit** `scripts/Npc.gd` + `scripts/Game.gd` with message `feat(032): pass live relationship roster to NPC goal selection`.

### Task 4: Decisions, ticket status, and full regression sweep

**Files:**
- Modify: `doc/idea-v2-decisions.md` (add "Ticket 032 — relationship-driven goal decisions"); `doc/tickets/032-relationship-driven-npc-goals.md` (tick all checkboxes).

**Interfaces:**
- Consumes: harness results from Tasks 1–3.

- [ ] **Step 1: Record the four user-approved decisions verbatim** (current-goal + deterministic fallback; negative enemy weight with base fallback; resolver thresholds; player included) plus the mutual-romance-gate ruling and the roster re-wire on load.
- [ ] **Step 2: Tick all six ticket checkboxes.**
- [ ] **Step 3: Re-run all v2 harnesses 021–031 as regressions** (`run_dialogue_schema_tests.ps1`, `run_traits_and_dialogue_tests.ps1`, `run_conversation_helper_tests.ps1`, `run_conversation_ui_tests.ps1`, `run_settings_manager_tests.ps1`, `run_main_menu_tests.ps1`, `run_load_game_tests.ps1`, `run_pause_menu_tests.ps1`, `run_modloader_dual_root_tests.ps1`, `run_options_tests.ps1`, `run_mods_menu_tests.ps1`) and the three v1 harnesses. Expected: each prints its own success marker with no `[NNN] FAIL`.
- [ ] **Step 4: Commit** docs with message `docs(032): record decisions, close ticket, confirm regressions`.

### Task 5: Code review and handoff

- [ ] **Step 1: Run the `code-review-expert` skill on the branch** and save its report to `doc/code-review/codereview-ticket-032-relationship-driven-npc-goals.md`.
- [ ] **Step 2: Grade findings by user impact; fix Critical/Important with RED→GREEN tests, ledger the rest.**
- [ ] **Step 3: Ask the user for final verification, merge, and push approval.** Do not push before approval; after an approved push, mark GitHub issue #32 complete.
