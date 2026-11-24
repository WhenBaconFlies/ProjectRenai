# Code Review: Ticket 014 (dialogue filtering + pool + player trigger) — working tree vs master

- **Branch:** `master` (changes are uncommitted working-tree edits)
- **Base:** `master` (merge-base = current `HEAD`; review is of `git diff` + untracked files)
- **Changed files:** 11 (7 modified, 4 new)
- **Findings:** 5 unique (Critical: 0, High: 0, Medium: 4, Low: 1)
- **Reviewer:** code-review-expert (two independent passes merged, deduplicated and evidence-audited)

## Findings

### 1. [Medium][Architecture] Selection signal fired after unlock — ticket 015 would resolve outside the interaction
- **Location:** `scripts/Game.gd:186-187` (pre-fix)
- **Evidence:** `doc/tickets/014-dialogue-filtering-pool-trigger-design.md:104-105` specifies "emit `dialogue_topic_selected(...)` for ticket 015, then close and unlock", but the code called `_close_conversation()` before `dialogue_topic_selected.emit()`. With that order, a 015 handler applying deltas/feedback would run after the player was unlocked and the target unfrozen — contrary to the user's rule that the player cannot act until the interaction is complete.
- **Problem:** The documented 014→015 contract and the player-lock guarantee were inverted.
- **Recommendation:** Emit the signal first, then close. **Fixed:** statements swapped (`scripts/Game.gd:191-192`); headless check "player and NPC stay locked while 015 receives the signal" passes.

### 2. [Medium][Bug] Skipped class transition teleports a conversation-frozen NPC out of the conversation
- **Location:** `scripts/Game.gd:338-341`, `scripts/Npc.gd:117-127` (pre-fix)
- **Evidence:** `_on_state_changed()` loops every NPC calling `set_ai_enabled(false)` + `move_to(target)` with no busy check (during skip; same for the missed-lead path). `move_to()` unconditionally assigned `global_position` and `instance.position`; `_conversation_busy` only short-circuited `_physics_process`, so it could not stop a teleport.
- **Problem:** The user-specified "target NPC stays in place while talking" was violated when a period boundary arrived mid-conversation.
- **Recommendation:** Defer a class snap requested while conversation-busy and apply it on release. **Fixed:** `Npc.move_to()` stores `_pending_move_to` when busy; `set_conversation_busy(false)` applies it. Headless checks "class snap deferred while NPC is busy" and "deferred class snap applied on release" pass.

### 3. [Medium][Architecture] Player instance missing from the shared id map — 015/016 cannot resolve the initiator
- **Location:** `scripts/Game.gd:81-85,114` (pre-fix)
- **Evidence:** `_instances_by_id` was populated only from spawned NPCs in `_setup_npcs()`; `_setup_player_instance()` built `_player_instance` separately, yet `show_pool()`/`show_empty()` captured `initiator_id = "player"` and `_on_topic_selected()` emitted it. `_stats_for()` already special-cased the player, confirming the asymmetry.
- **Problem:** The pair-agnostic `(initiator_id, target_id)` seam emitted an id that could not be resolved to an instance for delta application, including player-as-target in 016.
- **Recommendation:** Register the player instance in `_instances_by_id`. **Fixed:** added in `_setup_player_instance()`; headless check "player instance resolves through the shared id map" passes.

### 4. [Medium][Bug] Negative `min_affection` gates silently ignored
- **Location:** `scripts/DialogueFilter.gd:42` (pre-fix) — reported independently by both reviewers
- **Evidence:** `scripts/DialogueTopic.gd:31-32` documents `min_affection` as `-100..100` with `0 = no gate`; the filter used `if topic.min_affection > 0 and ...`, so a mod topic with `min_affection = -20` ("must not be an enemy") accepted a pair at `-100`. Shipped `.tres` files all use 0, so the original 53 checks did not exercise it.
- **Problem:** Legitimate negative thresholds were inert.
- **Recommendation:** Gate on `!= 0` for affection only (mood/familiarity ranges start at 0). **Fixed:** `scripts/DialogueFilter.gd:42-44`; headless checks for enemy rejection, acceptance at the bound, and zero-as-no-gate pass.

### 5. [Low][Bug] `build_pool()` null-dereferences the initiator on the play-mode seed path
- **Location:** `scripts/DialogueFilter.gd:85` (pre-fix)
- **Evidence:** `is_eligible()` fails closed for a null initiator (`DialogueFilter.gd:31`), but with the default `seed_value = -1` the code read `initiator.instance_id` unguarded. The previous checks always passed an explicit seed and a valid instance, so the branch was uncovered; ticket 016's NPC-initiated path may not have an initiator instance at this point.
- **Problem:** A public helper usable by 016 could crash where its sibling function fails closed.
- **Recommendation:** Use a null-safe initiator id when seeding. **Fixed:** `scripts/DialogueFilter.gd:85-88`; headless check "build_pool is null-initiator safe on play seed path" passes.

## Evidence Audit

- Findings 1–5 — SUPPORTED: each cites exact pre-fix lines, the documented contract or schema range, and a concrete behavioural consequence; all five were reproduced as regression checks.
- Both reviewers reported the negative-affection bug; deduplicated into finding 4.
- No vague or unsupported claims were retained.
- **Verdict: PASS — 0 unsupported findings.**

## Verification context (not findings)

- Headless Godot 4.2.1 after all fixes: `CHECKS=61 FAILURES=0`, `ALL_014_CHECKS_PASSED`; temporary verification script removed per repo convention.
- `DebugStart.tscn` and `Game.tscn` load with no parse errors. Normal headless launch still prints pre-existing `NavigationServer map query failed because it was made before first map synchronization` errors from ticket 013's NPC pathfinding; unrelated to 014 and unchanged by it.
- Visual appearance of the pool panel (colours, layout) is not verifiable headlessly; needs an in-editor/user visual check.
