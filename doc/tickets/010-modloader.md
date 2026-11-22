# 010: ModLoader

**What to build:** A `ModLoader` autoload that scans `res://mods/` at startup, validates each mod's `mod.json` (name, version, author, entry script, dependencies, content list), resolves dependencies in topological order with cycle detection, registers the mod's resources into the appropriate registries, and supports enable/disable flags. Invalid or missing-dependency mods are logged and skipped without crashing. v1 is add-only (no override). Includes one sample mod to exercise the full path.

**Blocked by:** 004 (CharacterTemplate + Trait schemas)

**Status:** ready-for-agent

- [ ] Mods in `res://mods/` are discovered at startup
- [ ] A mod with a valid `mod.json` has its resources registered
- [ ] A mod missing `mod.json` or with an unloadable entry is skipped with a log, no crash
- [ ] Missing dependencies cause the mod to be skipped with a clear log
- [ ] Cyclic dependencies are detected and rejected
- [ ] Disabled mods are skipped
- [ ] The sample mod's character appears in the registry after load
- [ ] Dependency resolution order is topological