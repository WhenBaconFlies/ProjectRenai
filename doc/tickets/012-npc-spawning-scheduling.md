# 012: NPC spawning & scheduling

**What to build:** Spawn 3–5 NPCs from character templates (via the ModLoader registry) into the map, each with a per-instance schedule mapping period → named map marker. On period change, NPCs move to their class location and attendance is recorded. NPCs use the same instance shape as the player.

**Blocked by:** 011 (Day state machine), 007 (Minimal base content)

**Status:** ready-for-agent

- [ ] 3–5 NPCs spawn from template IDs at map spawn
- [ ] Each NPC has a per-instance schedule (period → named map marker)
- [ ] On period change, NPCs move to their scheduled class location
- [ ] Attendance is recorded for each NPC per period
- [ ] NPC instance references its template by stable template ID
- [ ] A missing template on load is a recoverable error (no crash)