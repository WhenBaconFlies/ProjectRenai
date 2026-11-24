## AudioManager
##
## Global singleton for music and SFX playback and volume. Ticket 025 adds the
## typed master-volume seam that SettingsManager drives on startup and on write;
## playback itself remains a later ticket. Volume is stored linearly (0..1) and
## converted to dB for the Master bus, with 0 treated as muted.
extends Node

## Godot's built-in Master bus index.
const MASTER_BUS: int = 0
## dB used for a fully silent (0.0) linear volume.
const SILENT_DB: float = -80.0

## Neutral starting volume. The authored default lives in
## SettingsManager.DEFAULT_MASTER_VOLUME and is applied on autoload startup;
## keeping this neutral avoids a second source of truth for the setting.
var _master_volume: float = 1.0


func _ready() -> void:
	set_master_volume(_master_volume)


## Set the master volume (clamped to 0..1) and apply it to the Master bus.
func set_master_volume(value: float) -> void:
	_master_volume = clampf(value, 0.0, 1.0)
	var silent: bool = _master_volume <= 0.0
	var db: float = SILENT_DB if silent else linear_to_db(_master_volume)
	AudioServer.set_bus_volume_db(MASTER_BUS, db)
	AudioServer.set_bus_mute(MASTER_BUS, silent)


## Current master volume in linear 0..1 form.
func get_master_volume() -> float:
	return _master_volume
