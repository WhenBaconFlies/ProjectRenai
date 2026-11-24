# Code Review: Ticket 015 (threshold resolution + meters + feedback) — working tree vs master

- **Branch:** `master` (changes are uncommitted working-tree edits)
- **Base:** `master` (merge-base = current `HEAD`; review is of `git diff` + untracked files)
- **Changed files:** 10 (7 modified, 3 new; excluding the temporary verification script)
- **Findings:** 2 unique (Critical: 0, High: 0, Medium: 1, Low: 1)
- **Reviewer:** code-review-expert (two independent passes merged, deduplicated and evidence-audited)

## Findings

### 1. [Medium][Bug] Unknown stat id in a `recipient_modifier` fail-open — matches every recipient
- **Location:** `scripts/DialogueResolver.gd:88-89` (pre-fix)
- **Evidence:** Both reviewers independently reproduced the same defect. Code was:
  ```gdscript
  if kind == "stat":
      matched = target.get_stat(id) >= int(modifier.get("min", 0))
  ```
  `NpcInstance.get_stat()` (`scripts/NpcInstance.gd:98-99`) returns `0` for any key absent from `stats`, and `min` defaults to `0`, so `0 >= 0` is true. Probe with a misspelled id and no `min`:
  ```
  PROBE unknown_stat_mod effective_difficulty=7 recipient_scale=1.5
  PROBE get_stat_unknown=0
  ```
  This is the opposite of the resolver's deliberate fail-closed handling for unknown trait ids (`:91`) and unknown orientations (`:248-258`).
- **Problem:** A mod authoring typo silently raised difficulty and scaled deltas for every recipient, with no warning.
- **Recommendation:** Require the stat key to exist on the target instance. **Fixed:** `scripts/DialogueResolver.gd:88-92` now uses `target.stats.has(id) and target.get_stat(id) >= int(modifier.get("min", 0))`, with a comment explaining the typo case; this still permits mod-added stats. Regression checks "unknown stat id does not match" and "unknown stat id leaves scale at 1" pass (66/66 suite).

### 2. [Low][Process] Ticket status and acceptance checkboxes not closed out
- **Location:** `doc/tickets/015-threshold-resolution-meter-updates.md:7` and `:9-14` (pre-fix)
- **Evidence:** File still read `**Status:** ready-for-agent` with six `- [ ]` boxes despite the implementation being present and the headless suite passing (`checks=66 fails=0 / ALL_015_CHECKS_PASSED`). Ticket 014 established the convention (`doc/tickets/014-dialogue-filtering-pool-trigger.md:7,9-14, Verification line`).
- **Problem:** Tracker state did not reflect shipped work.
- **Recommendation:** Mark the ticket done, tick all six boxes (noting the user-approved fifth relationship type), and add a Verification line. **Fixed:** ticket file updated with `Status: done`, six `- [x]` boxes, and a Verification line citing the design doc and decisions.

## Evidence Audit

- Findings 1–2 — SUPPORTED: each cites exact pre-fix lines, a reproduced behaviour (headless probe / file contents) and a concrete consequence; both fixed and re-verified.
- Both reviewers reported the fail-open stat defect independently; deduplicated into finding 1.
- Secondary suggestion from one reviewer — "consider requiring an explicit positive `min` for `kind='stat'`" — not retained as a finding: `min` is documented in `scripts/DialogueTopic.gd` and the design doc as an optional stat threshold defaulting to 0 ("matches any recipient with this stat"), and unknown ids are now rejected by finding 1's fix, so this is intended behaviour rather than a defect.
- No vague or unsupported claims retained.
- **Verdict: PASS — 0 unsupported findings.**

## Verification context (not findings)

- Headless Godot 4.2.1 after all fixes: `checks=66 fails=0`, `ALL_015_CHECKS_PASSED`. Coverage: roll formula and seeded die, success/failure boundary, margin bounds (×1/×2/cap), modifier trait/stat matching + non-match + unknown-id + combined-scale clamp, both-party meter/mood writes and clamps, all five relationship types including failed-mutual→Friend, relationship re-derivation after update, feedback UI visibility/hide, toggle on/off through `Game.gd`, authored `.tres` modifier load, and scene wiring/launch.
- Real launch path `--headless --quit-after 10` loads `DebugStart.tscn` → `Game.tscn` with no parse/runtime errors from ticket 015. The pre-existing `NavigationServer map query failed because it was made before first map synchronization` errors from ticket 013's NPC pathfinding remain unchanged.
- The visual appearance of the feedback panel (layout, colours, readability at the game's zoom level) is not verifiable headlessly; it needs an in-editor/user visual check before push.
- Temporary `verify_015.gd` is removed after the run, per repo convention.
