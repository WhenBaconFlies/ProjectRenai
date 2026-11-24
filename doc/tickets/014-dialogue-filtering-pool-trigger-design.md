# 014: Dialogue filtering + pool + player trigger — Design

Companion to `doc/tickets/014-dialogue-filtering-pool-trigger.md`. Decisions are
recorded in `doc/idea-v1-decisions.md` under "Ticket 014".

## Approach

Data-first and testable, mirroring tickets 011–013: register the authored
dialogue resources so there is one source of topics, add a pure `DialogueFilter`
helper that owns condition evaluation and pool randomization, add an `Area2D`
proximity component and a small selection UI, then keep all wiring in the
existing `Game.gd`. No resolution, deltas or relationship derivation — ticket
015 owns those and receives a single selection signal.

Two alternatives were rejected: putting eligibility logic in each topic resource
(data becomes code, no reusable seam for NPC-initiated interactions in 016), and
inlining filtering plus UI construction in `Game.gd` (untestable at the seam the
spec asks for).

User decisions that override the default design: a conversation does **not**
pause the clock or other NPCs; the player and the chosen NPC are locked/frozen
until the player picks a topic or cancels; the chosen NPC is flagged busy for
016; and E works at any time of day while in proximity.

## Components

### `ModLoader` (`scripts/ModLoader.gd`)

`_register_base_content()` also scans `res://resources/dialogue/` and registers
every `.tres`/`.res` `DialogueTopic` into `TYPE_DIALOGUE` with owner `"base"`,
before mod content, on every `load_mods()`. The two authored topics and the
sample mod's topic are then all reachable through `get_all(TYPE_DIALOGUE)`.
Invalid resources log and skip; add-only conflicts keep the first registration.

### Player state (`scripts/Game.gd`)

Build an `NpcInstance` for the player at startup: `instance_id` is
`TimeManager.player_character_id` (`"player"` by default); the template is
resolved through `ModLoader` using `player_template_id`, then `char:alex`, then
`player_template_path`. Stats and mood come from that template. This gives the
filter an initiator of exactly the same shape as the target NPC, so the
pipeline stays pair-agnostic `(initiator_id, target_id)`. Ticket 017 persists
this instance instead of creating a second player shape.

### `DialogueFilter` (`scripts/DialogueFilter.gd`, `class_name DialogueFilter extends RefCounted`)

Pure, headless-testable, no scene tree or autoload globals.

- `is_eligible(topic, initiator, target, initiator_template, target_template) -> bool` — all conditions must pass:
  - `min_mood` against `initiator.mood`;
  - `min_familiarity` / `min_affection` from the initiator's directed meter toward `target.instance_id`, read-only (no meter is created by filtering);
  - `required_interests` / `required_traits`: every id must occur in the union of both templates' trait ids and tags (Trait resources or plain strings). A missing template contributes no keys, so a topic with such a requirement fails closed;
  - `required_stat` / `required_stat_min` against the initiator's stats.
- `build_pool(...) -> Array` — eligible topics from the supplied array are
  shuffled with a seeded `RandomNumberGenerator`, then sliced to
  `clampi(randi_range(3, 5), 1, eligible.size())`. Zero eligible returns an
  empty array. An explicit `seed_value` makes headless tests deterministic;
  play uses a tick-derived seed so repeated conversations vary.
- `trait_keys(template)` and the meter lookup are private helpers; neither
  mutates an instance.

### `InteractionComponent` (`scripts/InteractionComponent.gd`, `class_name InteractionComponent extends Area2D`)

Child of Player in `Game.tscn`, with a generated/exposed circular
`CollisionShape2D` (`interaction_radius`, default ~28 px). Tracks `body_entered`
/ `body_exited` for bodies in group `npc`; the nearest tracked NPC is the
current candidate. On the new `interact` input action (E + gamepad fallback,
also defensively registered at runtime like Player's movement actions) it emits
`interaction_requested(target: Npc)` when a candidate exists. No candidate, or
an already-open interaction, means the event is ignored. Exposes
`set_enabled(bool)` so `Game.gd` can ignore input while a pool is open.

### `DialoguePoolUI` (`scripts/DialoguePoolUI.gd`, `class_name DialoguePoolUI extends Control`)

Placed under a `CanvasLayer` in `Game.tscn`. `show_pool(topics, initiator_id, target_id)`
builds one button per topic plus a **Cancel** button; `show_empty()` shows
"No appropriate topics right now." with only a dismiss/Cancel button. Number
keys 1–5, Esc and mouse clicks all work. Signals: `topic_selected(topic, initiator_id, target_id)`
and `cancelled`. `hide_pool()` clears the buttons and hides the panel. The UI
owns no game state beyond being open/closed.

### `Player` (`scripts/Player.gd`)

`set_input_locked(bool)` zeroes velocity and makes `_physics_process` ignore the
movement vector while locked. Unlocking does not synthesize input. This is the
player half of the user's "player cannot move or interact until complete" rule.

### `Npc` (`scripts/Npc.gd`)

`set_conversation_busy(bool)` freezes physics movement for the duration of a
conversation without touching `instance.current_goal`, `goal_destination` or the
navigation agent target, so the NPC resumes its goal after the conversation.
`is_busy()` returns true for an active goal **or** a conversation; a new
`is_conversation_busy()` gives ticket 016 an exact "already talking" gate.

### `Game` (`scripts/Game.gd`, `scenes/Game.tscn`)

- Creates the player instance and resolves the player template at setup time.
- Owns the active conversation (`_dialogue_target`), locks the player and the
  target NPC, and disables the InteractionComponent while the pool is open.
- On `interaction_requested`: resolve the target's template, call
  `DialogueFilter.build_pool()` over `ModLoader.get_all(TYPE_DIALOGUE)`, and show
  the pool (or the empty fallback). Both parties are passed as ids + instances.
- On `topic_selected`: emit `dialogue_topic_selected(topic, initiator_id, target_id)`
  for ticket 015, then close and unlock. No roll, deltas or meter writes.
- On `cancelled` (including the empty fallback): close and unlock, emit no
  selection. Invalid/freed target mid-selection closes gracefully.
- Game.tscn gains `Player/InteractionComponent` and `DialogueLayer/DialoguePoolUI`.

`project.godot` gains the `interact` action (physical E = 69, gamepad button 0).

## Acceptance mapping

| Checkbox | Covered by |
|----------|------------|
| Pressing E near an NPC opens a pool of 3–5 topics | InteractionComponent + `DialogueFilter.build_pool()` + pool UI |
| Topics filtered by conditions | `DialogueFilter.is_eligible()` |
| Pool randomized within eligible topics | seeded shuffle + random 3–5 slice |
| Player can select a topic | UI buttons/number keys → `topic_selected` |
| No eligible topics handled gracefully | `show_empty()` + Cancel, no crash |
| Trigger only fires when NPC in proximity | Area2D candidate tracking; no candidate = no event |

## Verification plan

Headless Godot 4.2.1 scripts (removed after the run, per repo convention) assert:
all five condition gates accept/reject correctly; a topic requiring a missing
trait fails closed; required stat uses the initiator; pool size is 3–5, never
exceeds eligible count, and varies with the seed; zero eligible yields an empty
pool; filtering never creates a meter; E with no NPC in range does nothing; E
with an NPC in range opens the pool; selection emits exactly one
`dialogue_topic_selected` with the right ids and no meter changes; Cancel emits
none; the player stays locked and the NPC stays frozen+busy until the
interaction closes, then both resume; the NPC's goal and nav target survive the
conversation; and `DebugStart.tscn` → `Game.tscn` launches with no parse/runtime
errors. Result recorded in the final report.
