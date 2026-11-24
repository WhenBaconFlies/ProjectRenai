# 028: Pause Menu + Escape gate

**What to build:** An in-game `PauseMenu` overlay opened with Escape **only when no conversation is open** — while a conversation is open, Escape continues to cancel it. The pause menu offers Save As (create a named slot from the current live state via `SaveManager.save_slot(name)`), Load (route to the Load Game screen), Options, Mods, and Resume. Pausing halts the day clock while open and resumes it cleanly.

**Blocked by:** 024 (ConversationUI overlay + Game wiring), 026 (Main Menu + New Game routing)

**Status:** ready-for-agent

- [ ] Escape opens the pause overlay when no conversation is open
- [ ] Escape cancels a conversation instead of pausing when one is open
- [ ] Save As creates a named slot from the current live game state
- [ ] Load/Options/Mods/Resume route correctly
- [ ] The day clock is halted while paused and resumes without drift
- [ ] No overlap between the conversation overlay and the pause overlay