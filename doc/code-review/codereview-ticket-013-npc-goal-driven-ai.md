# Code Review: Ticket 013 (NPC goal-driven AI) — working tree vs master

- **Branch:** `master` (changes are uncommitted working-tree edits)
- **Base:** `master` (merge-base = current `HEAD`; review is of `git diff` + untracked files)
- **Changed files:** 10 (8 modified, 2 new)
- **Findings:** 6 (Critical: 0, High: 2, Medium: 1, Low: 3)
- **Reviewer:** code-review-expert (independent reviewer pass merged and evidence-audited)

## Findings

### 1. [High][Bug] Interest-based goal selection is inert for half the roster and three of four hangouts
- **Location:** `scripts/NpcAi.gd:93-107`, `resources/maps/map_school.tres:139-144`, `resources/characters/char_riley.tres:18`, `resources/characters/char_taylor.tres:18`
- **Evidence:** `NpcAi._interest_keys()` only accepts traits with `category == "interest"` (`NpcAi.gd:99`). Authored categories are: `trait_likes_sports` = `interest` (`trait_likes_sports.tres:9`), `trait_studious` = `skill` (`trait_studious.tres:9`), `trait_athletic` = `skill` (`trait_athletic.tres:9`), `trait_outgoing`/`trait_shy` = `personality`, `trait_dislikes_noise` = `dislike`. The default roster (`NpcSpawner.gd:18-23`) is `char:sam`, `char:jordan`, `char:riley`, `char:taylor`:
  - `char_riley.tres:18` → studious (skill) + dislikes noise (dislike) → **zero** interest keys.
  - `char_taylor.tres:18` → outgoing (personality) + studious (skill) → **zero** interest keys.
  - sam/jordan only get `sports`/`active`, which match only `hangout_courtyard` (`map_school.tres:141`). `hangout_library` (`academic/study/quiet`), `hangout_cafeteria` (`social/food`) and `hangout_garden` (`quiet/nature/calm`) can never receive an interest bonus.
  - The 52-check verification only asserted that sam prefers courtyard; it never asserted distinct distributions per template, so this passed unnoticed.
- **Problem:** The "interests steer destination choice" decision is only effective for 2 of 4 NPCs and 1 of 4 destinations, despite the ticket checkbox being marked done.
- **Recommendation:** Broad `_interest_keys()` to collect tags from all preference-bearing traits (all categories except `dislike`), so Riley's `academic`/`study` and Taylor's `social`/`academic` tags match the authored hangouts (or author additional `category = "interest"` traits with those tags). Add a headless assertion that `select_goal()` yields different weighted distributions for `char:taylor` vs `char:jordan` at a fixed seed.

### 2. [High][Bug] Stall recovery is dead code when a navigation path exists — NPC can remain pinned indefinitely
- **Location:** `scripts/Npc.gd:170-183`, `scripts/Npc.gd:247-265`
- **Evidence:** Steering recomputes `path_usable` every physics frame (`Npc.gd:175-179`) and assigns `_using_fallback = false` whenever the agent reports a path. `_update_stall()` sets `_using_fallback = true` on no progress (`Npc.gd:253-255`), but the next frame overwrites it. Because `_fallback_elapsed` only increments while `_using_fallback` is true (`Npc.gd:262-263`), it advances ~1 frame per 1.5 s and never reaches `fallback_timeout_sec = 2.5`; the `evaluate_goal()` branch at `Npc.gd:256-258` is unreachable when a path exists. The current authored map is saved only by tangent sliding (`Npc.gd:201-206`, `224-232`); a wedge with no slide collision, or a modded map, leaves the NPC frozen.
- **Problem:** The documented "no progress → straight-line fallback → re-evaluate" guarantee does not hold for the exact case it was written for (a nav path that leads into a collider).
- **Recommendation:** Introduce a separate `_force_fallback: bool` set by `_update_stall()` when no progress is detected; make steering use `if _force_fallback or not path_usable: target_point = destination`; increment `_fallback_elapsed` while forced and call `evaluate_goal()` after `fallback_timeout_sec`. Clear `_force_fallback` in `evaluate_goal()`, `set_ai_enabled()` and `_arrive()`. Add a headless case with an NPC pinned against a collider and a "usable" path that asserts re-evaluation within ~4 s.

### 3. [Medium][Architecture] Loading into a `FREETIME*` state cannot enable AI, and `goal_destination` is dead on read
- **Location:** `scripts/Game.gd:107-114`, `scripts/TimeManager.gd:358-376`, `scripts/Npc.gd:80-88`, `scripts/NpcInstance.gd:61-63`
- **Evidence:** The only `set_ai_enabled(true, ...)` call site is `Game._on_state_changed()` (`Game.gd:107-114`). `TimeManager.restore_day_snapshot()` assigns `_state` directly (`TimeManager.gd:362`) and emits `state_changed` only from `_enter_state()` (`TimeManager.gd:441`), which restore does not call. `Npc.setup()` (`Npc.gd:80-88`) copies `instance.position` but never applies `instance.goal_destination` to the agent. `NpcInstance.gd:61-62` claims the field exists "so ticket 017 can restore an in-flight goal".
- **Problem:** After a ticket-017 load into a free-time state, no signal fires, so NPCs stay motionless despite a running clock; the serialized goal/destination is never consumed.
- **Recommendation:** Add a `Game.sync_ai_state()` that enables/disables AI from the current state and call it both from `_on_state_changed()` and from the ticket-017 restore path; in `Npc.setup()`, set `navigation_agent.target_position = instance.goal_destination` when `current_goal` is non-empty so the field is actually consumable.

### 4. [Low][Bug] AI keeps running when BREAK or DAYEND is entered
- **Location:** `scripts/Game.gd:116-119`, `scripts/TimeManager.gd:259-271`
- **Evidence:** `_on_state_changed()` returns early when `period_number_for(new_state) == 0` (`Game.gd:117-119`) before calling `set_ai_enabled(false)` at `Game.gd:124`. `TimeManager.start_break_day()` enters `BREAK` via `_enter_state()` (`TimeManager.gd:271`), which emits `state_changed`; `period_number_for(BREAK) == 0` (`TimeManager.gd:383-395`). The BREAK clock is explicitly paused (`TimeManager.gd:177-178`), so NPCs keep pathfinding while time is frozen.
- **Problem:** NPCs continue moving during a paused break/day-end transition, and the in-progress goal is discarded on resume.
- **Recommendation:** Disable AI for every non-free-time state: move the `npc.set_ai_enabled(false)` loop above the `if period <= 0: return` guard.

### 5. [Low][Architecture] `_is_free_time_state()` ignores its `state` argument
- **Location:** `scripts/Game.gd:78-80`
- **Evidence:** The function returns `state > 0 and TimeManager.get_state_name().begins_with("FREETIME")`, reading global TimeManager state instead of the `state` value passed by the signal. A probe confirmed autoload enum access works (`ENUM_PROBE: 2 4 6` for `TimeManager.DayState.FREETIME1/2/3`), so the signal argument can be used directly. The current behavior depends on `_enter_state()` assigning `_state` before emitting (`TimeManager.gd:439-441`).
- **Problem:** A future caller that emits `state_changed` with a queued/legacy state, or a restore path that emits manually, would enable AI for the wrong state.
- **Recommendation:** Match against `TimeManager.DayState.FREETIME1/2/3` using the `state` argument (or add `TimeManager.is_free_time_state(state)`) instead of the state-name string.

### 6. [Low][Architecture] Relationship-goal deferral seam is disconnected
- **Location:** `scripts/NpcAi.gd:33-87`, `scripts/NpcAi.gd:119-120`
- **Evidence:** `relationship_candidates()` is defined but has no call site; `select_goal()` builds candidates only from hangout markers (`NpcAi.gd:48-87`).
- **Problem:** Tickets 014/015 must both implement the hook and discover/insert the integration point; the seam cannot be exercised or tested today even with an empty result.
- **Recommendation:** Call `relationship_candidates()` from `select_goal()` and fold any returned candidates into the weighted loop, so the extension point is live and covered by a headless assertion that it currently contributes zero candidates.

## Evidence Audit

- Finding 1 — SUPPORTED: exact `category` values in four trait `.tres` files, the two roster character files, the hangout tag dictionary, and the `NpcAi.gd:99` filter.
- Finding 2 — SUPPORTED: control-flow trace of `Npc.gd:175-183` vs `Npc.gd:249-265`; `_fallback_elapsed` is only incremented while a flag that is reset each frame.
- Finding 3 — SUPPORTED: single call site in `Game.gd`, direct `_state` assignment in `TimeManager.restore_day_snapshot()`, and absent target restore in `Npc.setup()`.
- Finding 4 — SUPPORTED: early return at `Game.gd:117-119` and `period_number_for()` mapping BREAK to 0.
- Finding 5 — SUPPORTED: source of `_is_free_time_state()` plus `ENUM_PROBE` command output proving enum access through the autoload.
- Finding 6 — SUPPORTED: no call sites for `relationship_candidates()` in `scripts/`.
- **Verdict: PASS** — 0 unsupported claims.

## Verification context (not findings)

- Headless scene verification: `CHECKS=52 FAILURES=0`, `ALL_013_CHECKS_PASSED` — hangout schema, deterministic seeded selection, interest/mood weighting for `char:sam`, snapshot round-trip, AI enable/disable across two free-time cycles, all 4 NPCs travelling 190–300 px over 10 s without sticking, and class-marker reseating.
- During that verification, tangent-slide recovery was added (`Npc.gd:224-232`) after two NPCs were observed pinned against the bench collider; travel rose from 13–18 px to 190–300 px over 10 s.
- Godot 4.2.1 headless launch exits 0 with no parse/runtime errors after cleanup of temporary verification scripts.
