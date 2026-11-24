# 026: Main Menu + New Game routing

**What to build:** A `MainMenu` scene with New Game, Load Game, Options, Mods Menu, and Quit, routed through `GameManager`. It becomes `run/main_scene`; `DebugStart.tscn` stays as a developer shortcut. New Game starts the default debug day directly via the existing fresh-start path (no wizard). Other menu buttons route to their screens (stubs are acceptable until those tickets land, but navigation must not crash). Quit closes the game.

**Blocked by:** 024 (ConversationUI overlay + Game wiring)

**Status:** complete

- [x] `MainMenu` is `run/main_scene` and displays the five buttons
- [x] New Game starts the default debug day with the shipped map and player template
- [x] Load Game, Options, and Mods Menu buttons route to their screens or a safe placeholder
- [x] Quit exits cleanly
- [x] DebugStart still launches the game directly for developers
- [x] No regression in the v1 day-loop harness launch path
