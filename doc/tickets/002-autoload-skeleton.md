# 002: Autoload skeleton (stubs)

**What to build:** Register the six autoload singletons (GameManager, SaveManager, TimeManager, ModLoader, AudioManager, LocalizationManager) as stubs so later tickets can fill in behaviour against stable entry points. The app must run with all autoloads initialized.

**Blocked by:** 001 (Project scaffolding)

**Status:** done

- [x] All six autoloads are registered in `project.godot`
- [x] Each autoload is a minimal script (GDScript) that loads without errors
- [x] App runs and autoloads are accessible from a scene
- [x] No null-reference or missing-script errors on startup