# Code Review: Ticket 012 (NPC spawning & scheduling) — working tree vs master

- **Branch:** `master` (changes are uncommitted working-tree edits)
- **Base:** `master` (merge-base = current `HEAD`; review is of `git diff` + untracked files)
- **Changed files:** 12 source/data/doc files (5 modified, 7 new); 2 temporary verification scripts excluded from review scope
- **Findings:** 4 (Critical: 0, High: 0, Medium: 1, Low: 3)
- **Reviewer:** code-review-expert (independent code-reviewer pass merged and evidence-audited)

## Findings

### 1. [Medium][Bug] Player template becomes a phantom NPC in the default-roster fallback
- **Location:** `scripts/ModLoader.gd:174-191`, `scripts/TimeManager.gd:532-540`, `resources/characters/char_alex.tres:9`
- **Evidence:** `_register_base_content()` registers every `CharacterTemplate` under `res://resources/characters/`, including `char_alex.tres` whose `id = "char:alex"`. Runtime log confirms all base characters are now in the registry: `[ModLoader] Loaded 1 mod(s); 7 resource(s) registered.` (4 base characters + 3 mod resources). `TimeManager._ensure_roster()` appends every registry character id and skips only `_player_id` (`"player"`):
  ```
  for resource in ModLoader.get_all(ModLoader.TYPE_CHARACTER):
      var id: String = str(resource.get("id"))
      if id.is_empty() or id == _player_id or _roster.has(id):
          continue
      _roster.append(id)
  ```
  The design doc states at `doc/tickets/012-npc-spawning-scheduling-design.md:79-80` that "`char:alex` is reserved for the player." The normal `Game.gd` path masks this because it calls `set_roster()` first (`scripts/Game.gd:59`), so the defect is latent in any path that calls `start_day()` without an explicit roster (headless tests / future load path).
- **Problem:** Registering base characters for ticket 012 made the 011 fallback roster treat the player's own template as an attendee, producing a phantom attendance/grade record for `char:alex`.
- **Recommendation:** In `TimeManager._ensure_roster()`, skip the player's template id: build a set from `player_template_id` and the `id` of the resource at `player_template_path`, and `continue` when a registry id is in that set. Keep the generic registry otherwise unchanged.

### 2. [Low][Robustness] Default NPC count silently depends on the sample mod being enabled
- **Location:** `scripts/NpcSpawner.gd:16-21`, `scripts/ModLoader.gd:317-324`, `doc/tickets/012-npc-spawning-scheduling-design.md:96`
- **Evidence:** `DEFAULT_TEMPLATE_IDS` hardcodes `"char:mod_sample"`, owned by `mods/sample_mod`. `ModLoader._load_one_mod()` skips a disabled mod (`enabled=false` or `.disabled` marker) at `scripts/ModLoader.gd:317-324`, so with the sample mod disabled only 3 templates remain and the spawner produces 3 NPCs. Verification currently asserts exactly 4 (`verify_ticket_012.gd`: `PASS: 4 NPCs spawn from template ids (got 4)`), so that assertion would fail in a disabled-mod configuration even though 3 NPCs still satisfy the ticket's 3–5 range.
- **Problem:** The authored base game has no deterministic NPC count independent of mod configuration.
- **Recommendation:** Author one additional base `CharacterTemplate` (e.g. `char_taylor.tres`) so the default template list can be filled entirely from `res://resources/`, and treat mod-provided templates as optional extras (or keep `char:mod_sample` as a 5th slot and relax the verification assertion to 3–5).

### 3. [Low][Documentation] `from_snapshot()` contract documents the wrong return value
- **Location:** `scripts/NpcInstance.gd:166-170`, `doc/tickets/012-npc-spawning-scheduling-design.md:32`
- **Evidence:** The comment reads `## Restore from a snapshot produced by snapshot(). Returns false on a malformed payload and never partially applies changes.` The implementation signature is `static func from_snapshot(data: Dictionary) -> NpcInstance:` and the malformed-payload branch is `return null` (`scripts/NpcInstance.gd:169-170`). The design doc likewise says `snapshot()/restore()` rather than `snapshot()/from_snapshot()`.
- **Problem:** A caller coding to the documented contract could compare against `false` rather than `null`.
- **Recommendation:** Change the comment to "Returns null on a malformed payload" and rename the design-doc reference to `snapshot()/from_snapshot()`.

### 4. [Low][Maintainability] Registry bucket name hardcoded in two runtime lookups
- **Location:** `scripts/NpcInstance.gd:137`, `scripts/NpcSpawner.gd:62`
- **Evidence:** Both call `loader.call("get_resource", "character", template_id)` with a literal bucket string instead of `ModLoader.TYPE_CHARACTER`. A bucket rename would silently turn every lookup into a "missing template" skip (`scripts/NpcSpawner.gd:63-72`). The compile-time constant cannot be used directly because autoload globals are unavailable to `--script`-loaded scripts, but runtime property access works — verified with `Godot --headless --script probe_const.gd`: `CONST_PROBE: get=character` and `CONST_PROBE: constant_map=character`.
- **Problem:** Two duplicated magic strings bypass the single source of truth for the registry bucket name.
- **Recommendation:** Resolve the constant at runtime via `str(loader.get("TYPE_CHARACTER"))` once in `NpcInstance._mod_loader()`'s callers (or add a small public helper returning the bucket name) and use it for both `get_resource()` calls.

## Evidence Audit

- Finding 1 — SUPPORTED: file references (`ModLoader.gd:174-191`, `TimeManager.gd:532-540`, `char_alex.tres:9`), quoted loop, runtime log line, and design-doc line 79.
- Finding 2 — SUPPORTED: `NpcSpawner.gd:16-21`, `ModLoader.gd:317-324`, and verification output `4 NPCs spawn ... (got 4)`.
- Finding 3 — SUPPORTED: `NpcInstance.gd:166-170` comment vs `return null` at line 170; design doc line 32.
- Finding 4 — SUPPORTED: `NpcInstance.gd:137`, `NpcSpawner.gd:62`, plus command output proving `loader.get("TYPE_CHARACTER")` returns `"character"`.
- **Verdict: PASS** — 0 unsupported claims.

## Verification context (not findings)

- `Godot --headless --script verify_ticket_012.gd --quit-after 5`: `CHECKS=66 FAILURES=0`, `ALL_012_CHECKS_PASSED`.
- `Godot --headless --script verify_ticket_012_launch.gd --quit-after 60`: `LAUNCH_PATH_OK: scene=res://scenes/Game.tscn npcs=4 clock_running=true`.
- Tier round-trip: `TIER_ROUNDTRIP: save_err=0 loaded_tier=close` after setting `tier = "far"` then `ResourceSaver.save`/`ResourceLoader.load` — confirms runtime-only tier is not persisted.
- No Critical or High findings; all 7 ticket acceptance checkboxes verified passing.
