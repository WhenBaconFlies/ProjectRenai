# 011: Day state machine + TimeManager + skip + attendance/grade stub

**What to build:** An explicit day state machine (Period1→FreeTime1→Period2→FreeTime2→Period3→FreeTime3→Period4→DayEnd→Save→NextDay) driven by `TimeManager` with a real-time clock. Skip advances to the next period boundary. On period change, attendance is recorded and a grade stub computes a small stat bonus from attendance + INT/WIS. NPCs' attendance is simulated (perfect in v1 — their only goal is to attend).

**Blocked by:** 008 (Map renderer), 002 (Autoload skeleton)

**Status:** ready-for-agent

- [ ] State machine transitions through all periods in order
- [ ] `TimeManager` drives period advancement on a real-time clock
- [ ] Skip advances to the next period boundary (time jumps, no simulation in skipped class time)
- [ ] Attendance is recorded per period
- [ ] Grade stub computes a small stat bonus from attendance + INT/WIS
- [ ] NPC attendance is simulated (perfect) in v1
- [ ] DayEnd triggers an autosave + manual save prompt
- [ ] Break days are represented as a separate state (not exercised in v1)