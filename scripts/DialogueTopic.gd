class_name DialogueTopic
extends Resource

## DialogueTopic
##
## A single data-driven dialogue topic stored as a `.tres` resource. Carries its
## own eligibility conditions, the stat checked during resolution, a difficulty,
## and success/failure deltas applied to both parties' directed meters. A
## developer can create and save instances of this in the Godot editor, and
## modders can add new topics by dropping `.tres` files.


## --- Identity ---

## Stable topic id (e.g. "topic:compliment_01"). Used for registry/mod linkage.
@export var id: String = ""

## Text shown to the player for this topic (or a localization key).
@export var text: String = ""


## --- Conditions (eligibility) ---
## A topic is eligible only when all of its conditions pass for the pair.

## Minimum mood of the initiator (0-100). 0 = no mood gate.
@export var min_mood: int = 0

## Minimum familiarity between the two parties (0-100). 0 = no familiarity gate.
@export var min_familiarity: int = 0

## Minimum affection between the two parties (-100..100). 0 = no affection gate.
@export var min_affection: int = 0

## Interest ids that must be present among the parties for eligibility.
## Empty = no interest requirement.
@export var required_interests: PackedStringArray = PackedStringArray()

## Trait ids that must be present among the parties for eligibility.
## Empty = no trait requirement.
@export var required_traits: PackedStringArray = PackedStringArray()

## Required stat name (one of strength/dexterity/constitution/intelligence/wisdom/charisma).
## Empty = no stat requirement.
@export var required_stat: String = ""

## Minimum value of `required_stat` for eligibility. Ignored when `required_stat` is empty.
@export var required_stat_min: int = 0


## --- Resolution ---

## Stat used in the threshold check: stat + (familiarity / 10) + random(0..5) >= difficulty.
## One of strength/dexterity/constitution/intelligence/wisdom/charisma. Empty = no stat bonus.
@export var checked_stat: String = ""

## Difficulty threshold for the resolution check.
@export var difficulty: int = 0


## --- Deltas (success) ---

## Affection delta applied on success (to both parties' directed meters).
@export var affection_delta_success: int = 0

## Familiarity delta applied on success.
@export var familiarity_delta_success: int = 0

## Mood delta applied on success.
@export var mood_delta_success: int = 0


## --- Deltas (failure) ---

## Affection delta applied on failure.
@export var affection_delta_failure: int = 0

## Familiarity delta applied on failure.
@export var familiarity_delta_failure: int = 0

## Mood delta applied on failure.
@export var mood_delta_failure: int = 0


## --- Recipient modifiers (ticket 015) ---
##
## Data-driven influence of the *recipient's* traits/stats on resolution. Each
## entry is a Dictionary with these keys (unspecified keys use the default):
##   "id": String          trait id / trait tag, or a stat name (required)
##   "kind": String        "trait" (default) or "stat"
##   "min": int            stat-only threshold (default 0)
##   "difficulty": int     added to effective difficulty when matched (default 0)
##   "delta_scale": float  multiplied into every delta the recipient receives
##                         (default 1.0; combined scale clamped to 0.25–2.0)
## An empty list means authored difficulty and verbatim deltas, so existing
## topics keep their original behaviour.
@export var recipient_modifiers: Array = []
