# 015: Threshold resolution + deltas + meter/mood updates + feedback — Design

Companion to `doc/tickets/015-threshold-resolution-meter-updates.md`. Decisions are
recorded in `doc/idea-v1-decisions.md` under "Ticket 015".

## Approach

Pure resolver + thin wiring + small feedback panel. `DialogueResolver` owns every
mutation and derivation and is driven only by resources and ids, so it can be
exercised headlessly without a scene tree. `Game.gd` connects to the
`dialogue_topic_selected` signal it already emits for ticket 014 and does nothing
but look up the two instances/templates, call the resolver and optionally show
feedback. This mirrors `DialogueFilter` from 014 and keeps 016's NPC-initiated path
pair-agnostic. Alternatives rejected: resolution inside `Game.gd` (no test seam)
and resolution inside `DialogueTopic` (data becomes code, hurts modding).

## Components

### `DialogueTopic` (`scripts/DialogueTopic.gd`)

Adds `@export var recipient_modifiers: Array = []`. Each entry is a Dictionary:

| key | type | default | meaning |
|-----|------|---------|---------|
| `id` | String | — | trait id / tag, or a stat name |
| `kind` | String | `"trait"` | `"trait"` or `"stat"` |
| `min` | int | `0` | stat-only: recipient must have stat ≥ `min` |
| `difficulty` | int | `0` | added to effective difficulty when matched |
| `delta_scale` | float | `1.0` | multiplied into every delta the recipient receives |

Empty list keeps authored difficulty and verbatim deltas. `topic_compliment.tres`
authors one `trait:outgoing` modifier (`difficulty=1`, `delta_scale=1.2`) so the
seam is visible in the playable slice.

### `DialogueResolver` (`scripts/DialogueResolver.gd`, `class_name ... extends RefCounted`)

Static, pure (no scene tree, no autoload globals) except reading resources passed
in. Public API:

- `resolve(topic, initiator, target, initiator_template, target_template, seed_value := -1) -> Dictionary`
- `relationship_type(instance, other, template, other_template) -> String`
- constants for the five relationship names and the clamp/scale bounds.

Resolution steps:
1. Effective difficulty = `topic.difficulty` plus matching `recipient_modifiers`.
2. `stat_bonus = checked_stat.is_empty() ? 0 : initiator.get_stat(checked_stat)`;
   `familiarity_bonus = initiator's directed familiarity / 10`; `die = rng.randi_range(0, 5)`;
   `roll = stat_bonus + familiarity_bonus + die`; `margin = roll - effective_difficulty`;
   success iff `margin >= 0`.
3. `margin_scale = clampf(1 + absf(margin)/5, 1, 2)`; apply to affection only.
4. Per-party deltas: initiator gets `base × margin_scale`; recipient additionally
   gets `recipient_scale` (combined clamp 0.25–2.0) on affection, familiarity and
   mood. All values `roundi`-ed.
5. Apply to both directed meters and both global moods, clamped
   (Fam 0–100, Aff −100..100, Mood 0–100). Missing meters are created.
6. Derive both parties' relationship types *after* the write and include
   before/after snapshots in the result.

### `InteractionFeedbackUI` (`scripts/InteractionFeedbackUI.gd`, `class_name ... extends Control`)

Small centred panel under a new `FeedbackLayer` CanvasLayer in `Game.tscn`.
`show_result(result, initiator_name, target_name)` renders Success/Failure, topic
text, roll breakdown, both parties' Familiarity/Affection/Mood before→after and
relationship changes. Auto-dismiss after `display_sec` (default 3.5 s); clicking
the panel dismisses early. Root is `MOUSE_FILTER_IGNORE` so only the panel catches
input; hidden when the toggle is off.

### `Game` (`scripts/Game.gd`, `scenes/Game.tscn`)

- `@export var show_relationship_feedback: bool = true` plus
  `set_relationship_feedback_enabled(bool)` / `is_relationship_feedback_enabled()`.
- Connects its own `dialogue_topic_selected` signal to `_on_dialogue_topic_selected`.
- Resolves both ids through `_instances_by_id` (014 already registers the player),
  picks the right template per side, calls `DialogueResolver.resolve()`, emits
  `dialogue_resolved(result)` and shows feedback when enabled.
- Game.tscn gains `FeedbackLayer/InteractionFeedbackUI`.

## Acceptance mapping

| Checkbox | Covered by |
|----------|------------|
| Selecting a topic runs the threshold check and reports success/failure | `DialogueResolver.resolve()` roll + result `success` |
| Margin scales the affection delta | bounded multiplicative `margin_scale` |
| Affection/familiarity/mood deltas apply to both parties | both directed meters + both moods, clamped |
| Relationship type re-derived after update | `relationship_type()` after the write; five types incl. Acquaintance |
| Feedback shown after interaction by default | `show_relationship_feedback = true` + feedback panel |
| Feedback toggle respected | exported flag + runtime setter/getter; off hides the panel |

## Verification plan

Headless Godot 4.2.1 scripts (removed after the run, per repo convention) assert
the roll formula with a seeded die, success/failure boundaries, margin bounds,
modifier match/no-match/clamping, both-party deltas and clamps, all five
relationship types plus the failed-mutual→Friend fallthrough, feedback panel
visibility and the on/off toggle, and the DebugStart→Game launch path.
