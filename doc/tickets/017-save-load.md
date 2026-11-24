# 017: Save/Load

**What to build:** Persist the whole game state as a Godot Resource (`.tres`/`.res`) at DayEnd (autosave + manual, unlimited slots in `user://`): current day, period/state, player instance, NPC instances, directed meters, positions, mood, stats. Reload restores instance state identically with template linkage by stable ID. A missing template on load is a recoverable error. Save version field for forward compatibility.

**Blocked by:** 015 (Threshold resolution + deltas + meter/mood updates + feedback)

**Status:** done

- [x] Save at DayEnd writes a Godot Resource file to `user://`
- [x] Autosave and manual save both work
- [x] Unlimited slots are supported
- [x] Reload restores player/NPC state (stats, mood, meters, positions, period) identically
- [x] Template linkage is preserved across save/load (stable IDs, not paths/UIDs)
- [x] A missing template on load is a recoverable error (no crash)
- [x] Save version field is present for forward compatibility
