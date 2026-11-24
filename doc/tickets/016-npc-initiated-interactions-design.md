# 016: NPC-initiated interactions — Design

Companion to `doc/tickets/016-npc-initiated-interactions.md`. Decisions are recorded in
`doc/idea-v1-decisions.md` under "Ticket 016".

## Approach

Pure helper + thin wiring + reuse of the 014/015 seams. A new `NpcInitiation` (RefCounted,
static methods) owns everything that can be decided from resources and ids: outgoingness
scoring, initiator eligibility, weighted target selection and the random pool pick.
`Game.gd` owns only the scene-tree side effects: the periodic check, the busy flags that
freeze NPC bodies, the cooldowns and the hold timers. The chosen topic is emitted through
the existing `dialogue_topic_selected` signal, so ticket 015's `DialogueResolver` remains
the single place that rolls the threshold and writes both parties' directed meters.

Rejected: initiation logic inside `Game.gd` (no headless test seam) and inside `Npc`
(scene-coupled, would duplicate the dialogue pipeline).

## Components

### `scripts/NpcInitiation.gd` (`class_name NpcInitiation extends RefCounted`)

Static, pure, no scene tree or autoload globals:

- `outgoingness(template: CharacterTemplate) -> int` — count distinct positive trait
  id/tag keys minus distinct negative ones. Positive: `trait:outgoing`, `outgoing`,
  `sociable`, `extrovert`, `extroverted`. Negative: `trait:shy`, `shy`, `introvert`,
  `introverted`, `reserved`. Keys come from `DialogueFilter.trait_keys()` so ids and tags
  behave as in 014/015. Tags `social`/`quiet` are intentionally omitted (`trait_shy`
  carries `social`).
- `can_initiate(instance, template, conversation_busy, forced_travel) -> bool` —
  outgoingness ≥ `MIN_OUTGOINGNESS` (1), valid instance, not talking, not in forced class
  travel. An ordinary hangout goal does not block.
- `target_weight(initiator, target, initiator_template, target_template, from: Vector2, to: Vector2) -> float`
  — base + directed familiarity/10 × weight + target outgoingness × weight + linear
  proximity falloff (0 beyond `PROXIMITY_RADIUS`).
- `select_target(candidates: Array, seed: int) -> String` — seeded weighted pick from
  `{ id, weight }` dictionaries; `""` when none.
- `pick_topic(pool: Array, seed: int) -> DialogueTopic` — seeded single random pick.

All randomness uses a caller-supplied `RandomNumberGenerator` seed so headless runs are
reproducible; play seeds from the day number plus an attempt counter.

### `scripts/Npc.gd` (small addition)

- `is_forced_destination() -> bool` — read-only getter for the existing `_forced_destination`
  flag, so `Game` can exclude NPCs mid class-travel without exposing internals.

### `scripts/Game.gd` (wiring)

New exported/tunable values: `npc_initiation_enabled` (default `true`),
`npc_initiation_check_interval_sec` (2.0), `npc_initiation_hold_sec` (2.0),
`npc_initiation_cooldown_sec` (8.0). Proximity radius is a `const` on `NpcInitiation`
(`PROXIMITY_RADIUS = 160.0`), not a scene export; changing it is a code edit.

Runtime state: `_initiation_elapsed`, `_initiation_attempts`, `_initiation_busy` (id set),
`_initiation_cooldowns` (id → seconds), `_active_initiations` (array of
`{ initiator_id, target_id, remaining }`).

- `_process(delta)` also advances initiation timers; a check runs at most once per interval,
  only during `FREETIME*`, and is skipped while the player's own pool is open.
- Each check builds initiator candidates from NPCs that pass `can_initiate()`, have no
  cooldown, and are not busy; targets are the player plus all NPCs minus the initiator and
  all busy ids. Player target is skipped while a player conversation is open.
- For each eligible initiator (seeded order): compute weights, pick a target, build the
  eligible pool with `DialogueFilter.build_pool()`, pick one topic at random, mark both
  ids busy, freeze NPC participants with `set_conversation_busy(true)`, record the hold,
  set the initiator cooldown and emit `dialogue_topic_selected`. An empty pool or no
  candidate simply skips that initiator — no crash, no busy flags.
- Hold/cooldown timers tick every frame; on expiry busy flags are cleared (NPC bodies
  released, so the 014 pending class-snap can apply). Leaving free time clears active
  initiations and busy flags so no state leaks into class.
- `_on_interaction_requested()` additionally rejects a target in `_initiation_busy`, so
  the player cannot start a second conversation with someone already talking.

The feedback panel (015) shows NPC-initiated outcomes **only when the player is one of
the two parties**: the resolver still runs for NPC↔NPC interactions and emits
`dialogue_resolved`, but their results do not replace the player-facing HUD. Multiple
player-involving results are queued by `InteractionFeedbackUI` and displayed one after
another, so the approved concurrency cannot silently overwrite an unread outcome.

## Acceptance mapping

| Checkbox | Covered by |
|----------|------------|
| Initiates during free time when not busy | `_process` interval gated on FREETIME* + `can_initiate` |
| Target selection weighs outgoingness and familiarity | `target_weight()` (plus user-approved proximity) |
| Random pick from eligible pool | `build_pool()` → `pick_topic()` with seeded RNG |
| Roll + deltas apply to both parties | existing `DialogueResolver.resolve()` via `dialogue_topic_selected` |
| Can target player or another NPC | target candidate list includes both |
| No crash/duplicate if target interacting | `_initiation_busy` + `is_conversation_busy()` + forced-travel gate |

## Verification plan

Headless Godot 4.2.1 scripts (removed after the run, per repo convention) assert outgoing
scores, gating flags, weighting monotonicity, seeded selection, Game-level initiation in
free time, both parties' meters changing, player/NPC targets, duplicate suppression,
empty-pool/no-candidate safety, and the launch path; plus editor scan and main-scene smoke.
Any step the user prefers to check in the editor will be called out explicitly.
