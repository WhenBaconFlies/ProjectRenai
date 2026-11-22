# 018: Day-loop integration & acceptance verification

**What to build:** The full day runs end-to-end through all periods, free time, NPC interactions, and save/load, satisfying every acceptance criterion in the spec. Add an integration test at the highest seam (spawn → move → talk → save → reload) via `DebugStart.tscn` and verify all 10 acceptance criteria pass.

**Blocked by:** 017 (Save/Load)

**Status:** ready-for-agent

- [ ] `DebugStart.tscn` runs a full day (Period1→FreeTime1→…→Period4→DayEnd→Save) without errors
- [ ] Player can move, approach an NPC, press E, pick from a 3–5 option pool, and see meters/mood update with feedback
- [ ] At least one NPC initiates an interaction during free time
- [ ] Save at DayEnd and reload restores state identically with template linkage intact
- [ ] A dropped mod with valid `mod.json` is discovered and registered; invalid/missing-dep mod is skipped with log, no crash
- [ ] Disabling a mod excludes its resources
- [ ] Missing template on load is recoverable (no crash)
- [ ] Skip advances to the next period boundary
- [ ] Attendance + grade stub runs on period change without errors
- [ ] Code is commented describing functions/scripts
- [ ] Integration test (highest seam) is added and passing