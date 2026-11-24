# Code Review: ticket/029-modloader-dual-root-settings vs master

- **Branch:** `ticket/029-modloader-dual-root-settings`
- **Base:** `master` (merge-base: `5430c0362dc4939735675578c9184d1ebf2df27d`)
- **Changed files:** 8 (`scripts/ModLoader.gd`, `project.godot`, `tests/DayLoopIntegrationTest.gd`, new 029 harness, `doc/idea-v2-decisions.md`)
- **Findings:** 7 (Critical: 1, High: 0, Medium: 3, Low: 3)
- **Reviewer:** fresh-context `code-reviewer` subagent, merged through the `code-review-expert` workflow with `evidence-validator` pass. All claims below carry file:line evidence and/or reproduced command output.

## Findings

### 1. [Critical][Architecture] Bundled content can be overridden by a user mod

- **Location:** `scripts/ModLoader.gd:203-213`, `scripts/ModLoader.gd:328-335`, `scripts/ModLoader.gd:416-428`, `scripts/ModLoader.gd:117-123`; contract at `doc/idea-v2-decisions.md:169`.
- **Evidence:** runtime probe with a bundled-like root scanned first:
  ```
  PROBE loaded order: ["probe:user", "probe:user_dep", "probe:bundled"]
  [ModLoader] WARN: add-only conflict for 'dialogue:topic:probe' (mod 'probe:bundled'): already owned by mod 'probe:user'; skipping
  PROBE winner text: USER
  ```
  The branch's own harness demonstrates the ordering cause: `dual:depends` (ROOT_A) loads after `dual:user_dep` (ROOT_B) in T3, because `_load_one_mod()` registration follows Kahn order (`scripts/ModLoader.gd:212-213`) while add-only is decided at `register_resource()` (`scripts/ModLoader.gd:118`). The harness passes 16/16 because no fixture combines a dependent bundled mod with a conflicting user resource id.
- **Problem:** the approved cross-root contract ("res:// wins; user duplicate rejected") is not enforced for resource ids when a bundled mod has any dependency on a user mod.
- **Recommendation:** make conflict resolution root-aware instead of load-order-aware (e.g. carry a scan-root index on each manifest and let an earlier-root resource replace a later-root duplicate with a logged diagnostic), and add a regression case: bundled mod depends on a user mod, both declare the same resource id, assert the bundled resource wins.

### 2. [Medium][Bug] Settings-based disabling is only tested for a bundled-root mod

- **Location:** `tests/ModLoaderDualRootTest.gd:49-51`, `tests/ModLoaderDualRootTest.gd:132`, `tests/ModLoaderDualRootTest.gd:142`.
- **Evidence:** the only `set_mod_enabled()` calls target `dual:disabled` and `dual:cycle_disabled_a`, both written to `ROOT_A`; `ROOT_B` mods never receive a flag. Verified by reading the fixture calls at lines 130-144.
- **Problem:** a regression that consulted flags only for the first root would still pass all 16 checks, even though the ticket's motivation is disabling user-installed mods in a read-only export.
- **Recommendation:** add a `ROOT_B` fixture, set its flag to false, and assert both the absent resource and a `skipped`/`disabled` report entry.

### 3. [Medium][Bug] T8 claims cross-root cycle coverage but both cycle mods are in one root

- **Location:** `tests/ModLoaderDualRootTest.gd:83-86`, `tests/ModLoaderDualRootTest.gd:140-141`.
- **Evidence:** `_write_mod(ROOT_B, "cycle_a", ...)` and `_write_mod(ROOT_B, "cycle_b", ...)`; run log shows `SKIP cyclic dependency ... dual:cycle_a, dual:cycle_b` from a single-root pair.
- **Problem:** ticket line 12 requires cycle handling across both roots; `_resolve_order()` is never exercised on a cross-root cycle.
- **Recommendation:** move `cycle_a` to `ROOT_A` and keep `cycle_b` in `ROOT_B`; keep the existing T8 assertions.

### 4. [Medium][Bug] Manifest `enabled: false` path is not covered by the new harness

- **Location:** `scripts/ModLoader.gd:348-349`, `tests/ModLoaderDualRootTest.gd:160`, `tests/ModLoaderDualRootTest.gd:177-178`.
- **Evidence:** `_write_mod()` declares `enabled_variant: Variant = null` but no fixture call at lines 130-144 passes it; the branch moves this check into `_enabled_mods()` without dedicated coverage.
- **Problem:** the author-level hard-disable branch is unverified by the ticket's own harness.
- **Recommendation:** add one fixture via `_write_mod(..., false)` and assert `skipped` with reason containing `manifest enabled=false`.

### 5. [Low][Process] Ticket acceptance boxes remain unchecked

- **Location:** `doc/tickets/029-modloader-dual-root-settings.md:9-14` — all six items are `- [ ]`, while completed tickets use `- [x]` (e.g. `doc/tickets/028-pause-menu-and-escape-gate.md:9-14`).
- **Problem:** ticket status does not match the implemented and verified state.
- **Recommendation:** check the six boxes and set status to `complete`.

### 6. [Low][Architecture] Contradictory `.disabled` contract remains in the decisions file

- **Location:** `doc/idea-v2-decisions.md:48` still says the Mods Menu "writes/removes the `.disabled` marker"; the new decision at `doc/idea-v2-decisions.md:168` and line 61 say markers are not the disable source.
- **Problem:** ticket 031 could implement the removed marker contract from the stale line.
- **Recommendation:** update line 48 to settings flags in `user://settings.cfg`.

### 7. [Low][Bug] T13 double-counts failures

- **Location:** `tests/ModLoaderDualRootTest.gd:121` uses `_check(_passed == EXPECTED_CHECKS - 1, ...)`, while `_check()` at line 265 increments `_passed` on success.
- **Evidence:** after one earlier failure `_passed == 14`, so T13 also fails, reporting two failures for one defect.
- **Problem:** noisy failure counts obscure which assertion actually broke.
- **Recommendation:** track the number of executed checks independently of `_passed`, or drop T13.
