# Code Review: Ticket 016 (uncommitted work) vs master

- **Branch:** master (working-tree changes for ticket 016)
- **Base:** master (merge-base: `7a2b7f0a6456c20e3570a12a2dce2f21557a72f5`)
- **Changed files reviewed:** `scripts/NpcInitiation.gd` (new), `scripts/Game.gd`, `scripts/Npc.gd`
- **Findings:** 4 (Critical: 0, High: 0, Medium: 2, Low: 2)

## Findings

### 1. [Medium][Bug] Initiation checks can fire during a skip's clock-halt beat

- **Location:** `scripts/Game.gd:547` (with `scripts/TimeManager.gd:205-215`)
- **Evidence:** `TimeManager.skip()` sets `_skip_in_progress = true` and holds the phase
  clock for `skip_pause_sec` while the state is still `FREETIME*`. The new condition
  `if npc_initiation_enabled and not _dialogue_open and _is_free_time_state(state):`
  does not consult `TimeManager.is_skipping()` (`scripts/TimeManager.gd:219`), so the
  accumulation/check at `scripts/Game.gd:548-551` can start an interaction inside the
  beat. Ticket 011's contract (recorded in `doc/idea-v1-decisions.md`, ticket 011,
  "Skip semantics") is that skipped time is not simulated. Reproduced with a temporary
  headless probe: `SKIP_BEAT_PROBE events=1 skip_active_at_emit=true skipping_now=true`.
- **Problem:** Skipping from a free-time phase can still simulate a conversation during
  the pause that is explicitly meant to be non-simulated.
- **Recommendation:** Add `and not TimeManager.is_skipping()` to the condition at
  `scripts/Game.gd:547` (the existing `_update_initiations()` timer tick can stay).
- **Status:** **Fixed** — guard added at `scripts/Game.gd:566`; post-fix headless check
  `no initiation during skip beat (review fix #1)` passes with the same interval/elapsed
  setup that reproduced the bug.

### 2. [Low][UX] Concurrent NPC interactions overwrite the single feedback panel

- **Location:** `scripts/Game.gd:295` and `scripts/InteractionFeedbackUI.gd:90-130`
- **Evidence:** `Game._on_dialogue_topic_selected()` calls `_feedback_ui.show_result()`
  for every resolution; `show_result()` overwrites `_title`, `_topic`, `_roll` and both
  party lines in place and only bumps a generation token to guard the auto-dismiss
  timer (`scripts/InteractionFeedbackUI.gd:122-129`). Ticket 016 deliberately allows
  multiple concurrent interactions (user decision recorded in
  `doc/idea-v1-decisions.md`, ticket 016, "Cadence"), so two initiations within the
  3.5 s display window leave only the last result visible.
- **Problem:** With the approved concurrency, earlier NPC-initiated outcomes are
  silently replaced before the player can read them.
- **Recommendation:** Queue results in `InteractionFeedbackUI` and show them in
  sequence, or append a compact one-line "X initiated with Y" history entry so each
  outcome remains observable.
- **Status:** **Fixed (user-directed)** — `scripts/Game.gd:298-299` now shows the panel
  only for player-involving interactions, and `scripts/InteractionFeedbackUI.gd` queues
  results (`show_result()` → `_queue`, `_advance()` shows the next). Post-fix checks
  `no panel for NPC->NPC (review fix #2a)`, `second result queued` and
  `queued result displayed` all pass.

### 3. [Medium][Bug] `_initiation_attempts` never resets, breaking per-day seed reproducibility

- **Location:** `scripts/Game.gd:89-91,371-374,510-516,629-632` (pre-fix)
- **Evidence:** The counter is documented as "checks this day (seed)" and increments at
  `Game.gd:371`, but `_clear_active_initiations()` and free-time entry only reset
  `_initiation_elapsed`. The seed `day * 104729 + attempts * 7919` therefore depends on
  every earlier day's check count.
- **Problem:** Replaying day N produces different seeded initiator ordering, target
  selection and topic picks than reaching day N through play.
- **Recommendation:** Reset `_initiation_attempts = 0` on a new day.
- **Status:** **Fixed** — connected `TimeManager.day_started` to `_on_day_started()`
  (`scripts/Game.gd:530-531,536-538`), which also clears cooldowns. Post-fix check
  `attempt counter resets on new day (review fix A)` passes.

### 4. [Low][Architecture] Design doc lists a tunable that is not exposed

- **Location:** `doc/tickets/016-npc-initiated-interactions-design.md:51-53` vs
  `scripts/NpcInitiation.gd:41-44`
- **Evidence:** The design listed `npc_initiation_proximity_radius` (160.0) as a `Game.gd`
  export; `Game.gd:53-60` exports only four values and `PROXIMITY_RADIUS` is a `const` on
  `NpcInitiation`.
- **Problem:** Documentation promises a verification seam that does not exist.
- **Recommendation:** Expose the export or correct the design doc.
- **Status:** **Fixed** — design doc now records the radius as an `NpcInitiation` constant,
  not a scene export.

## Notes (inherited, out of scope for ticket 016)

- `scripts/Game.gd:536` `_is_free_time_state(state)` reads `TimeManager.get_state_name()`
  instead of its `state` argument. Already recorded as an open ticket-013 review
  follow-up in `doc/idea-v1-decisions.md` (ticket 013, review follow-ups); not introduced
  here.
- `scenes/Game.tscn:18` overrides `show_relationship_feedback = false` against the
  documented default `true` (`scripts/Game.gd:40`). Pre-existing from ticket 015; worth
  confirming the intended shipped default before final delivery.

## Evidence Audit

1. [SUPPORTED] Finding 1 — file references: `scripts/Game.gd:547-551`,
   `scripts/TimeManager.gd:205-215,219`; contract in `doc/idea-v1-decisions.md`;
   probe output `SKIP_BEAT_PROBE events=1 skip_active_at_emit=true`.
2. [SUPPORTED] Finding 2 — file references: `scripts/Game.gd:295`,
   `scripts/InteractionFeedbackUI.gd:90-130`; concurrency decision in
   `doc/idea-v1-decisions.md`.
3. [SUPPORTED] Finding 3 — grep of all `_initiation_attempts` assignments (only the
   declaration and one increment pre-fix) plus `scripts/Game.gd:510-516,629-632`.
4. [SUPPORTED] Finding 4 — `doc/tickets/016-npc-initiated-interactions-design.md:51-53`
   vs `scripts/Game.gd:53-60` and `scripts/NpcInitiation.gd:44`.

**Verdict:** PASS — every finding cites concrete file:line evidence; no unsupported
claims retained.
