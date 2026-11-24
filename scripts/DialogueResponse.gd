class_name DialogueResponse
extends Resource

## DialogueResponse
##
## A data-driven spoken line stored as a `.tres` resource. In a player-initiated
## conversation it is the NPC's reaction to a chosen topic; in an NPC-initiated
## conversation its `text` is the player's spoken reply. Both roles use the same
## resource so modders author one kind of content for either direction.
##
## A response may be a **line-only reaction** (no roll, no deltas) or a normal
## roll with its own stat/difficulty/deltas. The rule is simple and deliberate:
## an empty `checked_stat` means line-only. Other roll fields may still be
## authored, but they are ignored while `checked_stat` is empty. This deliberately
## diverges from DialogueTopic, where an empty `checked_stat` only removes the
## stat bonus and the roll still applies deltas; a line-only response must be
## gated by is_line_only() before resolution. The single field gives the authoring
## pipeline one unambiguous switch.


## --- Identity ---

## Stable response id (e.g. "response:compliment_success_friend"). Used for
## registry/mod linkage; add-only duplicate-id rules apply.
@export var id: String = ""

## Spoken line. NPC's reaction for player-initiated talks; the player's reply
## line for NPC-initiated talks.
@export var text: String = ""


## --- Keying (fallback chain) ---

## Id of the topic this line answers. Empty = generic authored line usable for
## any topic (the last authored step before a code-generated fallback).
@export var topic_id: String = ""

## Outcomes this line matches: "success" and/or "failure". An empty array is a
## wildcard that matches any outcome, which is how an authored default for a
## topic is expressed.
@export var outcomes: PackedStringArray = PackedStringArray()

## Relationship band names this line matches. Values are the five derived types
## from DialogueResolver: Stranger, Acquaintance, Friend, Enemy, Lover. An empty
## array is a wildcard that matches any band. A response with a `topic_id` and
## both key arrays empty is that topic's authored default; one with no
## `topic_id` and both arrays empty is the generic authored line.
@export var relationship_bands: PackedStringArray = PackedStringArray()


## --- Optional roll fields ---

## Stat used in the threshold check: stat + (familiarity / 10) + random(0..5)
## >= difficulty. Empty = line-only reaction: no roll and no deltas are applied.
@export var checked_stat: String = ""

## Difficulty threshold for the resolution check. Ignored when line-only.
@export var difficulty: int = 0

## Affection delta applied on success (to both parties' directed meters).
## Ignored when line-only.
@export var affection_delta_success: int = 0

## Familiarity delta applied on success. Ignored when line-only.
@export var familiarity_delta_success: int = 0

## Mood delta applied on success. Ignored when line-only.
@export var mood_delta_success: int = 0

## Affection delta applied on failure. Ignored when line-only.
@export var affection_delta_failure: int = 0

## Familiarity delta applied on failure. Ignored when line-only.
@export var familiarity_delta_failure: int = 0

## Mood delta applied on failure. Ignored when line-only.
@export var mood_delta_failure: int = 0


## True when this response is a line-only reaction: no roll and no deltas.
## Defined as `checked_stat.is_empty()`; all other roll fields are ignored in
## that case, even when authored. Ticket 023 must generalize DialogueResolver
## to consume response-owned roll fields and call this before deciding to roll.
func is_line_only() -> bool:
	return checked_stat.is_empty()
