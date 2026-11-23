# Code Review: ticket/010-modloader vs master

- **Branch:** ticket/010-modloader
- **Base:** master (merge-base: 99305f1)
- **Changed files:** 8 (scripts/ModLoader.gd, mods/sample_mod/{mod.json,entry.gd,char_sample.tres,trait_sample.tres,topic_sample.tres}, doc/tickets/010-modloader.md, doc/idea-v1-decisions.md)
- **Findings:** 4 (Critical: 0, High: 0, Medium: 1, Low: 3)

## Findings

### 1. [Medium][Architecture] `load_mods()` is re-entrant: an entry hook can wipe registries mid-load
- **Location:** `scripts/ModLoader.gd:121`, `scripts/ModLoader.gd:129`, `scripts/ModLoader.gd:318`
- **Evidence:** `load_mods()` calls `_reset_registries()` (line 122) then iterates `for mod_id in order` (line 129) calling `_load_one_mod`. `_load_one_mod` calls `instance.call("register", self)` (line 318), handing the mod a reference to this autoload. Because `load_mods()` is public and has no in-progress guard, an entry script can call `loader.load_mods()` from `register()`, re-entering line 121 and clearing `_registries`, `_owners`, `_loaded_mods`, and `_last_report` while the outer loop is still running. Subsequent mods in `order` then fail their dependency check because `_loaded_mods` was emptied, and resources registered before the re-entry are lost. The final log also reports only the inner call's counts.
- **Problem:** A mod-controlled callback can silently invalidate the registry and cause false "missing dependency" skips for later mods.
- **Recommendation:** Add a `_is_loading: bool` guard: set it true at the start of `load_mods()`, return early (with a warning log) if already true, and clear it in an `else` / `dispose`-safe path at the end (or defer re-entrant requests with `call_deferred`). Keep the guard internal so entry hooks cannot bypass it.

### 2. [Low][Bug] Unused `folder_name` parameter in `_validate_manifest`
- **Location:** `scripts/ModLoader.gd:190`
- **Evidence:** `func _validate_manifest(parsed: Variant, folder_name: String) -> Dictionary:` — the body (lines 191–212) never references `folder_name`; the caller at line ~168 passes it but the error strings built inside do not include it.
- **Problem:** Dead parameter adds noise and makes validation errors less diagnosable (they do not name the mod folder).
- **Recommendation:** Either remove the parameter or use it in the returned reason strings (e.g. `"mod folder '%s': missing required field '%s'" % [folder_name, field]`), which also improves skip logs.

### 3. [Low][Bug] Cycle diagnostics mislabel downstream dependents as cycle members
- **Location:** `scripts/ModLoader.gd:248-253`
- **Evidence:** After Kahn's algorithm, `cycles` is filled with every mod id not in `order` (`if not order.has(str(id))`). That set includes both members of a cycle and any mods that merely depend (transitively) on the cycle. The log at line 251 says `SKIP cyclic dependency involving mod(s): %s` and each is reported with reason `"cyclic dependency"` (line 253), even for a dependent that has no cycle in its own edges.
- **Problem:** Operators troubleshooting a skipped mod get a misleading cause ("cyclic dependency" for a non-cyclic mod), which conflicts with the ticket's "clear log" intent for dependency failures.
- **Recommendation:** Distinguish the two (e.g. report members as `"cyclic dependency"` and the rest as `"depends on a mod in a dependency cycle"`), or reword the log to `"unresolved dependency cycle or dependency on a cyclic mod"` so the message is accurate for both sets.

### 4. [Low][Architecture] Diagnostics use inconsistent, colliding `mod` keys
- **Location:** `scripts/ModLoader.gd:178-180`, `scripts/ModLoader.gd:259-350`, `scripts/ModLoader.gd:369-370`
- **Evidence:** `_add_report()` entries from `_discover_mods` are keyed by **folder name** (missing manifest / invalid manifest / duplicate id), while entries from `_resolve_order` and `_load_one_mod` are keyed by **manifest id**. When two folders declare the same id, discovery emits `{mod: "dup", status: "skipped", reason: "duplicate mod id"}` and the load phase later emits `{mod: "dup", status: "loaded", ...}` for the surviving mod. A consumer that indexes `get_last_report()` by `mod` (as verification scripts naturally do) sees only the last entry and can miss the skip entirely.
- **Problem:** The report cannot unambiguously answer "was this mod skipped, and why?" in duplicate-id and mixed-key cases.
- **Recommendation:** Use one canonical key everywhere (the resolved mod id, or `"folder@<folder>"` when no valid id exists), and give each entry a distinct identity (e.g. add a `folder` field) so a duplicate-id skip and the surviving mod's load are separately addressable.

## Verification

- Headless Godot 4.2.1 (`D:\Godot\Godot_v4.2.1-stable_win64_console.exe`) verification script (temporary, removed after use): `ALL_010_CHECKS_PASSED`, exit code 0. Asserted all eight ticket criteria, including sample-mod registration, topological order (`z_dep` before `a_main`), missing-dependency skip, cycle rejection, disabled skip, missing-manifest skip, unloadable-entry skip, invalid-manifest skip, entry-hook execution, and add-only duplicate rejection.
- Headless launch-path script: `LAUNCH_PATH_OK`, exit code 0 — `DebugStart.tscn` hands off to `Game.tscn` with Player, MapRenderer, Minimap and FollowCamera present, and the sample mod remains registered after the scene change.
- Default launch (`--quit-after 5`) produced no parse or runtime errors; only ModLoader info logs.
- **Not verified:** the `.disabled` marker-file path (only `enabled=false` was exercised by the automated test); the enable/disable flag's runtime toggling is intentionally out of scope for v1.
