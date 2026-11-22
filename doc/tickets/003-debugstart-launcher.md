# 003: DebugStart launcher scene

**What to build:** A minimal debug launcher scene (`DebugStart.tscn`) that auto-starts a default day by loading `Game.tscn`, with no menu flow, so the slice is runnable and testable immediately. Autoloads must handle the "no save / fresh start" path this exercises.

**Blocked by:** 002 (Autoload skeleton)

**Status:** ready-for-agent

- [ ] `DebugStart.tscn` exists and is runnable
- [ ] Running it loads `Game.tscn` without errors
- [ ] Autoloads handle a fresh start (no save present) without crashing
- [ ] No menu flow is required to reach gameplay