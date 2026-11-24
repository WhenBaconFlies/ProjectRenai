# 033: v2 integration harness + v1 regressions

**What to build:** One persistent integration harness at the highest seam exercising v2 end to end: Main Menu/New Game → a player-initiated conversation (greeting, topic, reactive line, two-pick limit, both meters/mood, feedback) → an NPC-initiated single-reply talk → pause/Save As/reload → Options and Mods Menu operations → a relationship-driven goal. Assert external behavior only. Include a RED/GREEN proof on a core conversation check, then re-run v1's day-loop, chunk-renderer, and chunk-manager harnesses as regressions.

**Blocked by:** 024 (ConversationUI overlay + Game wiring), 027 (Load Game named-slot UI), 028 (Pause Menu + Escape gate), 030 (Options screen), 031 (Mods Menu), 032 (Relationship-driven NPC goals)

**Status:** ready-for-agent

- [ ] One harness covers every v2 acceptance criterion via the real menu/conversation entry points
- [ ] Both conversation shapes, turn limits, fallbacks, meters/mood, and relationship updates are asserted
- [ ] Save/reload via a named slot restores the full day state
- [ ] Options and Mods Menu changes persist and take effect per their rules
- [ ] Relationship-driven seek/avoid behavior is observed in free time
- [ ] A RED/GREEN proof is recorded for a core conversation check
- [ ] v1's three harnesses still pass with no regressions
- [ ] Harness uses marker-based pass/fail and portable launcher conventions from v1