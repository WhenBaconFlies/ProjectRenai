class_name DialogueGreeting
extends Resource

## DialogueGreeting
##
## A data-driven opening line stored as a `.tres` resource. A developer can
## create one in the Godot editor's "New Resource" dialog and a modder can add
## one by dropping a resource into a mod's `content` list. Eligibility is a set
## of independent gates: an empty collection or a boundary left at its default
## means "no restriction", so an author can narrow a greeting without having to
## specify every factor.
##
## This ticket (021) defines the schema and registry only. Ticket 023 consumes
## `weight` for seeded weighted selection and evaluates the eligibility gates.


## --- Identity ---

## Stable greeting id (e.g. "greeting:friend_morning"). Used for registry/mod
## linkage; add-only duplicate-id rules apply.
@export var id: String = ""

## Line the NPC speaks when opening a conversation (or a localization key).
@export var text: String = ""


## --- Eligibility ---

## Relationship type names that permit this greeting. Values are the five
## derived types from DialogueResolver: Stranger, Acquaintance, Friend, Enemy,
## Lover. Empty = any relationship type.
@export var relationship_types: PackedStringArray = PackedStringArray()

## Minimum speaker mood (0-100) for this greeting to be eligible. 0 = no gate.
@export var min_mood: int = 0

## Maximum speaker mood (0-100) for this greeting to be eligible. 100 = no gate.
@export var max_mood: int = 100

## TimeManager state names during which this greeting is eligible (e.g.
## "PERIOD1", "FREETIME2"). Empty = any period. The live period is derived by
## the conversation helper, not by this resource.
@export var periods: PackedStringArray = PackedStringArray()

## Trait ids/tags required for eligibility (checked against both parties).
## Empty = no trait requirement.
@export var required_traits: PackedStringArray = PackedStringArray()

## Interest ids/tags required for eligibility (checked against both parties).
## Empty = no interest requirement.
@export var required_interests: PackedStringArray = PackedStringArray()


## --- Selection ---

## Relative weight for seeded weighted selection among eligible greetings.
## Defaults to 1.0; a value <= 0 lets an author disable a greeting without
## deleting its resource. Consumed by ticket 023, not by the registry.
@export var weight: float = 1.0
