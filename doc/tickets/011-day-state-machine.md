# 011: Day state machine + TimeManager + skip + attendance/grade stub

**What to build:** An explicit day state machine (Period1→FreeTime1→Period2→FreeTime2→Period3→FreeTime3→Period4→DayEnd→Save→NextDay) driven by `TimeManager` with a real-time clock. Skip advances to the next period boundary. On period change, attendance is recorded and a grade stub computes a small stat bonus from attendance + INT/WIS. NPCs' attendance is simulated (perfect in v1 — their only goal is to attend).

**Blocked by:** 008 (Map renderer), 002 (Autoload skeleton)

**Status:** done

- [x] State machine transitions through all periods in order
- [x] `TimeManager` drives period advancement on a real-time clock
- [x] Skip advances to the next period boundary (time jumps, no simulation in skipped class time)
- [x] Attendance is recorded per period
- [x] Grade stub computes a small stat bonus from attendance + INT/WIS
- [x] NPC attendance is simulated (perfect) in v1
- [x] DayEnd triggers an autosave + manual save prompt
- [x] Break days are represented as a separate state (not exercised in v1)