# 029: ModLoader dual scan root + settings-based enable/disable

**What to build:** Extend `ModLoader` to scan both `res://mods/` (bundled base mods) and `user://mods/` (user-installed mods), registering all resources into the same typed buckets with the existing add-only conflict rules. Enable/disable state is read from `SettingsManager` mod flags rather than `res://` `.disabled` markers, so the toggle works in an exported build where `res://` is read-only. Dependency resolution, cycle detection, diagnostics, and entry hooks continue to work across both roots.

**Blocked by:** 025 (SettingsManager + ConfigFile persistence)

**Status:** ready-for-agent

- [ ] `ModLoader` scans both `res://mods/` and `user://mods/` and registers resources from both
- [ ] Enable/disable is read from settings flags, not `.disabled` markers
- [ ] Duplicate ids across roots are rejected add-only with a logged diagnostic
- [ ] Dependencies resolve topologically across both roots; cycles and missing deps skip cleanly
- [ ] Entry hooks and `get_last_report()` still work
- [ ] Headless tests exercise a synthetic `user://` mod tree without touching real content