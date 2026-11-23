class_name Item
extends Resource

## Item
##
## A placeable item (furniture, wall, prop, ...) stored as a `.tres` resource.
## Carries a `PackedScene` reference that the map renderer instantiates, plus
## sprite/collider data and properties used by the map editor. A developer can
## create and save instances of this in the Godot editor.


## --- Identity ---

## Stable item id (e.g. "item:desk_01"). Used for registry/mod linkage.
@export var id: String = ""

## Item type. One of: "furniture", "wall", "prop", "decoration", etc.
## Free-form string for modding.
@export var type: String = ""


## --- Instantiation ---

## PackedScene the map renderer instantiates when placing this item.
@export var packed_scene: PackedScene


## --- Sprite data ---

## Optional preview texture used by the map editor / UI without instantiating.
@export var sprite: Texture2D

## Pixel offset applied to the sprite relative to the item origin.
@export var sprite_offset: Vector2 = Vector2.ZERO

## Scale applied to the sprite.
@export var sprite_scale: Vector2 = Vector2.ONE


## --- Collider data ---

## Collision shape instantiated/used by the renderer for physics.
@export var collider_shape: Shape2D

## Pixel offset applied to the collider relative to the item origin.
@export var collider_offset: Vector2 = Vector2.ZERO


## --- Properties (furniture/walls) ---

## Whether this item blocks movement (e.g. walls, solid furniture).
@export var blocks_movement: bool = false

## Whether this item blocks sight/line-of-sight.
@export var blocks_sight: bool = false

## Whether the player/NPC can interact with this item.
@export var interactable: bool = false

## Free-form extra properties for modding/editor use (key -> value).
@export var properties: Dictionary = {}