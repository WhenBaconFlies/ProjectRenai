# 018: Day-loop integration & acceptance verification

**What to build:** The full day runs end-to-end through all periods, free time, NPC interactions, and save/load, satisfying every acceptance criterion in the spec. Add an integration test at the highest seam (spawn → move → talk → save → reload) via `DebugStart.tscn` and verify all 10 acceptance criteria pass.

**Blocked by:** 017 (Save/Load)

**Status:** done

- [x] `DebugStart.tscn` runs a full day (Period1→FreeTime1→…→Period4→DayEnd→Save) without errors
- [x] Player can move, approach an NPC, press E, pick from a 3–5 option pool, and see meters/mood update with feedback
- [x] At least one NPC initiates an interaction during free time
- [x] Save at DayEnd and reload restores state identically with template linkage intact
- [x] A dropped mod with valid `mod.json` is discovered and registered; invalid/missing-dep mod is skipped with log, no crash
- [x] Disabling a mod excludes its resources
- [x] Missing template on load is recoverable (no crash)
- [x] Skip advances to the next period boundary
- [x] Attendance + grade stub runs on period change without errors
- [x] Code is commented describing functions/scripts
- [x] Integration test (highest seam) is added and passing

## Verification

Persistent headless harness: `tests/run_integration.ps1` (boots `tests/IntegrationBootstrap.tscn` → real `DebugStart.tscn` → `Game.tscn`). 41/41 checks pass with `ALL_018_CHECKS_PASSED`. RED proof: temporarily emptying `DialogueFilter.build_pool()` failed 4 checks; reverted and re-verified 41/41.
