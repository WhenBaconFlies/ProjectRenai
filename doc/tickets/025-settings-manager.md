# 025: SettingsManager + ConfigFile persistence

**What to build:** A `SettingsManager` autoload backed by a `ConfigFile` at `user://settings.cfg`, holding volume, resolution/fullscreen, chunk config values (tier radii and tick rates), and language display. Reads apply on startup to `AudioManager`, the display, and `ChunkManager.config`; writes apply immediately from the Options screen with a restart notice where the engine requires it. Also stores mod enable/disable flags used by the Mods Menu and ModLoader. This is a foundation with no user-facing screen yet — verify persistence and application headlessly.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `SettingsManager` autoload loads and saves `user://settings.cfg` with typed getters/setters
- [ ] Volume, resolution/fullscreen, chunk config, language display, and mod flags are stored
- [ ] Settings apply immediately on write where possible (volume/chunk config), with a restart notice where required
- [ ] Missing/corrupt config falls back to defaults without crashing
- [ ] Headless checks round-trip every setting through save/reload