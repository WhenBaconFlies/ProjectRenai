# Main Menu + New Game routing (ticket 026) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `MainMenu` scene as `run/main_scene` that starts a fresh debug day, routes to Load Game / Options / Mods Menu placeholders, and quits, while keeping `DebugStart.tscn` and the v1 harness launch path untouched.

**Architecture:** All scene routing lives in `GameManager` via named scene constants and `show_*()` helpers; the menu scripts only emit button presses into those helpers. Placeholder scenes are intentionally minimal and will be replaced by tickets 027/030/031. A headless harness attached to `/root` drives the real scene swaps and checks external behavior only.

**Tech Stack:** Godot 4.2 / GDScript / `.tscn` built by hand, PowerShell marker-based harness runner.

**Spec:** `doc/tickets/026-main-menu-and-new-game.md`; `doc/idea-v2-spec.md`; `doc/idea-v2-decisions.md` (Menus and screens).

## Global Constraints

- GDScript only; no C# (v2 decision).
- `GameManager.start_fresh_day()` is the single fresh-start path; no New Game wizard.
- `DebugStart.tscn` remains a developer shortcut; v1 harness boots it explicitly via `GameManager.change_scene()`.
- Settings/Load/Mods screens are stubs in this ticket; full implementations belong to 027/030/031.
- Marker-based pass/fail harness (`ALL_026_CHECKS_PASSED`); Godot exit code is not authoritative.
- No push to GitHub without final user approval.

## Review Focus

1. Changing `run/main_scene` must not break the v1 harness, which boots `DebugStart.tscn` directly — task 4 adds that regression check.
2. Quit must be observable in headless without exiting the runner — task 2 adds `set_quit_action()` and the harness injects a fake.
3. Scene swaps from a `/root`-parented runner must complete before assertions — harness awaits two process frames after each route.
4. A stale button index or double press must not route twice — tests press each button once and assert the resulting scene name.
5. Placeholder navigation must never dead-end — each stub has a Back button routed to the main menu, exercised by the harness.

---

### Task 1: GameManager routing seams + main scene setting

**Files:**
- Modify: `scripts/GameManager.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: existing `change_scene(path)`, `start_fresh_day()`.
- Produces: constants `SCENE_MAIN_MENU`, `SCENE_LOAD_GAME`, `SCENE_OPTIONS`, `SCENE_MODS_MENU`, `SCENE_GAME`; helpers `show_main_menu()`, `show_load_game()`, `show_options()`, `show_mods_menu()`, `quit_game()`.

- [ ] **Step 1: Add scene path constants and route helpers to `GameManager.gd`** — each `show_*()` calls `change_scene(<matching constant>)`; `quit_game()` calls `get_tree().quit()`.
- [ ] **Step 2: Change `run/main_scene` in `project.godot` to `res://scenes/MainMenu.tscn`.**
- [ ] **Step 3: Verify** by grepping both files for the exact constants/setting.

### Task 2: MainMenu scene + script

**Files:**
- Create: `scenes/MainMenu.tscn`, `scripts/MainMenu.gd`

**Interfaces:**
- Consumes: `GameManager.start_fresh_day()`, `show_load_game()`, `show_options()`, `show_mods_menu()`, `quit_game()`.
- Produces: buttons named `NewGameButton`, `LoadGameButton`, `OptionsButton`, `ModsButton`, `QuitButton` with texts `New Game`, `Load Game`, `Options`, `Mods Menu`, `Quit`; `set_quit_action(action: Callable)` test seam.

- [ ] **Step 1: Write `MainMenu.gd`** with `@onready` button refs, `_ready()` signal connections, `_default_quit()` calling `GameManager.quit_game()`, and `set_quit_action()` mirroring `Game.set_npc_initiation_gate()`.
- [ ] **Step 2: Write `MainMenu.tscn`** — full-rect Control, background ColorRect, centered VBox, title Label, five Buttons with exact names/texts.
- [ ] **Step 3: Verify** the scene opens headlessly with no parse errors.

### Task 3: Placeholder screens

**Files:**
- Create: `scripts/PlaceholderScreen.gd`, `scenes/LoadGame.tscn`, `scenes/Options.tscn`, `scenes/ModsMenu.tscn`

**Interfaces:**
- Consumes: `GameManager.show_main_menu()`.
- Produces: scenes named `LoadGame`, `Options`, `ModsMenu`, each with `CenterBox/BackButton`; script export `screen_title` sets title and note text.

- [ ] **Step 1: Write `PlaceholderScreen.gd`** — sets title/note labels from `screen_title`, connects Back to `GameManager.show_main_menu()`, grabs focus.
- [ ] **Step 2: Write the three `.tscn` files** using the same layout as MainMenu with one title, one note, one Back button.
- [ ] **Step 3: Verify** all three scenes instantiate with no parse errors and route Back to `MainMenu`.

### Task 4: Headless harness + runner

**Files:**
- Create: `tests/MainMenuBootstrap.tscn`, `tests/MainMenuBootstrap.gd`, `tests/MainMenuTest.gd`, `tests/run_main_menu_tests.ps1`

**Interfaces:**
- Consumes: all routes above; `TimeManager.get_day_number()`, `get_state_name()`; `Map.id`.
- Produces: `ALL_026_CHECKS_PASSED` marker and `MAIN_MENU_026_OK` PowerShell result.

- [ ] **Step 1: Write bootstrap + runner** that adds the test node to `/root` and routes through `GameManager`.
- [ ] **Step 2: Write `MainMenuTest.gd`** asserting: main-scene setting; five buttons/texts; Quit calls injected action once; New Game enters `Game` with `current_save == null`, day 1 / `PERIOD1`, map `map:school_debug_large`; each placeholder route + Back; `DebugStart.tscn` still enters `Game` directly.
- [ ] **Step 3: Write `run_main_menu_tests.ps1`** using the v1 marker-based pattern and Godot at `D:\Godot`.
- [ ] **Step 4: Run harness; fix until all checks pass.**
- [ ] **Step 5: Re-run v1 harnesses (018/019/020) and the 021–025 harnesses as regressions.**
- [ ] **Step 6: Record decisions in `doc/idea-v2-decisions.md` and tick the ticket checkboxes.**

### Task 5: Code review

- [ ] **Step 1: Run `code-review-expert` skill on the branch; save the report to `doc/code-review/codereview-ticket-026-main-menu-and-new-game.md`.**
- [ ] **Step 2: Apply findings, re-run harnesses, and ask the user for final verification/push approval.**
