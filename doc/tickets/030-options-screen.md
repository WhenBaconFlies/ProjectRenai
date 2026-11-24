# 030: Options screen

**What to build:** An `Options` screen exposing Volume, Chunk settings (tier radii and tick rates), Language display, and Resolution (windowed presets + fullscreen). All changes write through `SettingsManager` and apply immediately where possible, with a restart notice only where the engine requires it. The relationship-feedback toggle is deliberately absent. English is shown as the current language with a disabled selector, making localization intent visible without claiming unimplemented languages.

**Blocked by:** 025 (SettingsManager + ConfigFile persistence)

**Status:** ready-for-agent

- [ ] Volume control is present and applies immediately
- [ ] Chunk settings expose tier radii and tick rates and apply immediately
- [ ] Resolution offers windowed presets plus fullscreen and applies per the immediacy rule
- [ ] Language row shows English as current with a disabled selector
- [ ] The relationship-feedback toggle is not present
- [ ] Settings persist across restart via `SettingsManager`