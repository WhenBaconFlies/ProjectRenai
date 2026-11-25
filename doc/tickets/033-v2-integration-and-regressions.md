# 033: v2 integration harness + v1 regressions

**What to build:** One persistent integration harness at the highest seam exercising v2 end to end: Main Menu/New Game → a player-initiated conversation (greeting, topic, reactive line, two-pick limit, both meters/mood, feedback) → an NPC-initiated single-reply talk → pause/Save As/reload → Options and Mods Menu operations → a relationship-driven goal. Assert external behavior only. Include a RED/GREEN proof on a core conversation check, then re-run v1's day-loop, chunk-renderer, and chunk-manager harnesses as regressions.

**Blocked by:** 024 (ConversationUI overlay + Game wiring), 027 (Load Game named-slot UI), 028 (Pause Menu + Escape gate), 030 (Options screen), 031 (Mods Menu), 032 (Relationship-driven NPC goals)

**Status:** complete

- [x] One harness covers every v2 acceptance criterion via the real menu/conversation entry points
- [x] Both conversation shapes, turn limits, fallbacks, meters/mood, and relationship updates are asserted
- [x] Save/reload via a named slot restores the full day state
- [x] Options and Mods Menu changes persist and take effect per their rules
- [x] Relationship-driven seek/avoid behavior is observed in free time
- [x] A RED/GREEN proof is recorded for a core conversation check
- [x] v1's three harnesses still pass with no regressions
- [x] Harness uses marker-based pass/fail and portable launcher conventions from v1

## Verification (2026-11-25)

- New harness: `tests/V2IntegrationBootstrap.tscn/.gd`, `tests/V2IntegrationTest.gd`, `tests/run_v2_integration_tests.ps1`; 63/63 checks, `ALL_033_CHECKS_PASSED`, `V2_INTEGRATION_033_OK`.
- RED/GREEN proof (two-pick limit, T17 + the self-referential count check): with `Conversation.MAX_TURNS` temporarily set to `3`, T17 failed with `passed=54 failed=2`, `SOME_033_CHECKS_FAILED` / `V2_INTEGRATION_033_FAILED`; restored to `2` → 56/56 GREEN. The reactive line is asserted by T14 but was not mutated.
- Regressions: all 15 harnesses 018–032 green (`INTEGRATION_018_OK`, `CHUNKMANAGER_019_OK`, `CHUNK_020_OK`, `DIALOGUE_021_OK`, `TRAITS_DIALOGUE_022_OK`, `CONVERSATION_023_OK`, `CONVERSATION_024_OK`, `SETTINGS_MANAGER_025_OK`, `MAIN_MENU_026_OK`, `LOAD_GAME_027_OK`, `PAUSE_MENU_028_OK`, `MODLOADER_DUAL_ROOT_029_OK`, `OPTIONS_030_OK`, `MODS_MENU_031_OK`, `NPC_GOALS_032_OK`).
- Config/slot isolation: harness writes only `user://v2_integration_settings.cfg` and slot `v2_integration`, both removed on finish.
- Code review: `doc/code-review/codereview-ticket-033-v2-integration-and-regressions.md` (12 evidence-backed findings, all applied). Mutation proofs covered T14/T20b/T21b/T13/T34b/T51b/T55b plus the abort/watchdog path; all production mutations were reverted and the suite re-verified green.
- Shipped 2026-11-25 with explicit user approval: branch `ticket/033-v2-integration-and-regressions` pushed, no-ff merge `1da8b0d` pushed to `origin/master`, GitHub issue #35 commented and closed as completed.
