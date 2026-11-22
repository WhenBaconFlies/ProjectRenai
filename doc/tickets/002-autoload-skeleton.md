# 002: Autoload skeleton (stubs)

**What to build:** Register the six autoload singletons (GameManager, SaveManager, TimeManager, ModLoader, AudioManager, LocalizationManager) as stubs so later tickets can fill in behaviour against stable entry points. The app must run with all autoloads initialized.

**Blocked by:** 001 (Project scaffolding)

**Status:** ready-for-agent

- [ ] All six autoloads are registered in `project.godot`
- [ ] Each autoload is a minimal script (GDScript or C#) that loads without errors
- [ ] App runs and autoloads are accessible from a scene
- [ ] No null-reference or missing-script errors on startup