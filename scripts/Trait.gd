class_name Trait
extends Resource

## Trait
##
## A single trait (skill/interest/dislike/personality) stored as a `.tres`
## resource. Carries a point cost, stat modifiers, and tags. A developer can
## create and save instances of this in the Godot editor.


## --- Identity ---

## Stable trait id (e.g. "trait:outgoing").
@export var id: String = ""

## Display name shown in-game.
@export var display_name: String = ""

## Category. One of: "skill", "interest", "dislike", "personality".
@export var category: String = ""


## --- Point cost ---

@export var point_cost: int = 0


## --- Stat modifiers (starting) ---

@export var strength_start_mod: int = 0
@export var dexterity_start_mod: int = 0
@export var constitution_start_mod: int = 0
@export var intelligence_start_mod: int = 0
@export var wisdom_start_mod: int = 0
@export var charisma_start_mod: int = 0


## --- Stat growth modifiers ---

@export var strength_growth_mod: float = 0.0
@export var dexterity_growth_mod: float = 0.0
@export var constitution_growth_mod: float = 0.0
@export var intelligence_growth_mod: float = 0.0
@export var wisdom_growth_mod: float = 0.0
@export var charisma_growth_mod: float = 0.0


## --- Tags ---
## Free-form tags used for filtering/matching (e.g. "social", "academic").

@export var tags: PackedStringArray = []
