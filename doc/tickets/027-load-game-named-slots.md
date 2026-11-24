# 027: Load Game named-slot UI

**What to build:** A `LoadGame` screen backed by the existing `SaveManager` slot API: list saved slots with their day/state, load a selected slot, and delete a slot. Creating a named slot is available only from the in-game pause overlay (ticket 028), writing the current live game state. F5/F9 debug hotkeys remain. Reloading a slot restores day/state, meters, positions, and template linkage as v1 already does.

**Blocked by:** 026 (Main Menu + New Game routing)

**Status:** complete

- [x] `LoadGame` lists named slots from `SaveManager.list_slots()` with readable metadata
- [x] Selecting a slot loads it via `GameManager` and enters the restored day
- [x] A slot can be deleted with confirmation
- [x] No live-state creation from the Main Menu; the UI explains creation happens in-game
- [x] F5/F9 still work during play
- [x] A reload restores state identically with template linkage (v1 regression)
