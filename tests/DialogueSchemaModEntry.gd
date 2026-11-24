## DialogueSchemaModEntry
##
## Test-only entry script for the synthetic mod used by ticket 021's headless
## harness. ModLoader requires every mod to declare an entry script; this one is
## deliberately a no-op so the fixture exercises content registration only,
## without emitting the sample mod's "character was not registered" warning.
extends RefCounted


func register(_loader) -> void:
	pass
