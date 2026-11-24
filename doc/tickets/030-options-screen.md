# 030: Options screen

**What to build:** An `Options` screen exposing Volume, Chunk settings (tier radii and tick rates), Language display, and Resolution (windowed presets + fullscreen). All changes write through `SettingsManager` and apply immediately where possible, with a restart notice only where the engine requires it. The relationship-feedback toggle is deliberately absent. English is shown as the current language with a disabled selector, making localization intent visible without claiming unimplemented languages.

**Blocked by:** 025 (SettingsManager + ConfigFile persistence)

**Status:** complete

- [x] Volume control is present and applies immediately
- [x] Chunk settings expose tier radii and tick rates and apply immediately
- [x] Resolution offers windowed presets plus fullscreen and applies per the immediacy rule
- [x] Language row shows English as current with a disabled selector
- [x] The relationship-feedback toggle is not present
- [x] Settings persist across restart via `SettingsManager`