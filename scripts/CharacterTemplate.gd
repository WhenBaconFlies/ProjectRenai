class_name CharacterTemplate
extends Resource

## CharacterTemplate
##
## Authored, shared, immutable-at-runtime character definition. Stored as a
## `.tres` resource and referenced by instances via a stable template id.
## A developer can create and save instances of this in the Godot editor.


## --- Identity ---

## Stable template id (e.g. "char:student_001"). Used for template<->instance linkage.
@export var id: String = ""

## Display name shown in-game.
@export var display_name: String = ""

## Gender identifier (free-form string for modding; e.g. "male", "female", "nonbinary").
@export var gender: String = ""

## Romantic orientation identifier (e.g. "hetero", "homo", "bi", "none").
@export var orientation: String = ""


## --- Appearance parts ---
## Part identifiers resolved by the renderer/authoring tools. Empty string = default.

@export var hair: String = ""
@export var eyes: String = ""
@export var mouth: String = ""
@export var skin_tone: String = ""
@export var outfit: String = ""


## --- Traits ---
## Traits attached to this character. Each Trait carries its own category.

@export var traits: Array = []


## --- Starting stats ---

@export var strength: int = 5
@export var dexterity: int = 5
@export var constitution: int = 5
@export var intelligence: int = 5
@export var wisdom: int = 5
@export var charisma: int = 5


## --- Stat growth modifiers (multipliers applied to growth from activities/interactions) ---

@export var strength_growth: float = 1.0
@export var dexterity_growth: float = 1.0
@export var constitution_growth: float = 1.0
@export var intelligence_growth: float = 1.0
@export var wisdom_growth: float = 1.0
@export var charisma_growth: float = 1.0


## --- Trait point cost for characters ---
## Trait point cost/budget associated with this character template.

@export var trait_point_cost: int = 0
