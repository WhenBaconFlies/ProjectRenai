# 031: Mods Menu

**What to build:** A `ModsMenu` screen listing installed mods from both scan roots with their name, version, author, dependencies, and load status, and an enable/disable toggle per mod that writes to `SettingsManager`. Toggling does not rescan live; it shows a restart-required notice and takes effect on the next launch. Disabled mods show as disabled and do not count as satisfied dependencies.

**Blocked by:** 029 (ModLoader dual scan root + settings enable/disable), 026 (Main Menu + New Game routing)

**Status:** ready-for-agent

- [ ] Installed mods from both roots are listed with manifest metadata and load status
- [ ] An enable/disable toggle writes the mod flag to settings
- [ ] Toggling shows a restart-required notice and does not rescan live
- [ ] Disabled mods are excluded on the next launch and from dependency satisfaction
- [ ] Invalid/skipped mods are visible with their diagnostic reason