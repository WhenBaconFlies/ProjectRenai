## PauseMenu
##
## In-game pause overlay (ticket 028). The live Game scene stays loaded while
## this is open: Game.gd freezes the clock, NPCs and player input, then calls
## open()/close() here. The menu owns no game state — named slots are written
## through SaveManager's live-state provider, and routes other than Load stay
## inside the overlay so the paused day is never stranded by a scene swap.
##
## Options and Mods embed the current placeholder scenes into PanelHost. They get
## an injected Back action returning to the pause menu; when tickets 030/031
## replace those scenes, the real screens appear here without touching this file.

class_name PauseMenu
extends Control

## Requested by the Resume and Load buttons. Game.gd resumes the live scene
## before handling a route; value is "resume" or "load".
signal route_requested(screen: String)

const OPTIONS_SCENE: String = "res://scenes/Options.tscn"
const MODS_SCENE: String = "res://scenes/ModsMenu.tscn"
const ROUTE_RESUME: String = "resume"
const ROUTE_LOAD: String = "load"

@onready var _box: PanelContainer = $Box
@onready var _status_label: Label = $Box/MenuBox/StatusLabel
@onready var _slot_input: LineEdit = $Box/MenuBox/SaveRow/SlotNameInput
@onready var _save_button: Button = $Box/MenuBox/SaveRow/SaveAsButton
@onready var _load_button: Button = $Box/MenuBox/LoadButton
@onready var _options_button: Button = $Box/MenuBox/OptionsButton
@onready var _mods_button: Button = $Box/MenuBox/ModsButton
@onready var _resume_button: Button = $Box/MenuBox/ResumeButton
@onready var _panel_host: Control = $PanelHost

## Currently embedded Options/Mods screen, or null when the main box is shown.
var _embedded: Node = null


func _ready() -> void:
	_save_button.pressed.connect(_on_save_as_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	_options_button.pressed.connect(_on_options_pressed)
	_mods_button.pressed.connect(_on_mods_pressed)
	_resume_button.pressed.connect(_on_resume_pressed)
	close()


## --- Lifecycle ---------------------------------------------------------------

func open() -> void:
	_close_embedded()
	_status_label.text = ""
	visible = true
	_resume_button.grab_focus()


func close() -> void:
	_close_embedded()
	visible = false


func is_open() -> bool:
	return visible


## Escape while paused: an embedded screen goes Back to the pause menu; with the
## main box open it resumes. Game.gd is the only caller, so the same Escape event
## cannot open and immediately close the overlay.
func handle_cancel() -> bool:
	if not is_open():
		return false
	if _embedded != null:
		_on_embedded_back()
	else:
		route_requested.emit(ROUTE_RESUME)
	return true


## --- Save As -----------------------------------------------------------------

func _on_save_as_pressed() -> void:
	var raw: String = _slot_input.text.strip_edges()
	if raw.is_empty():
		_set_status("Enter a slot name first.")
		return
	var lowered: String = raw.to_lower()
	if lowered == SaveManager.AUTOSAVE_SLOT or lowered == SaveManager.MANUAL_SLOT:
		_set_status("'%s' is reserved; choose another name." % raw)
		return
	# No reserved-slot bypass: a pause-menu save is always an ordinary named slot
	# built from the live state Game.gd supplies to SaveManager.
	if SaveManager.save_slot(raw):
		var stored: String = SaveManager.get_save_path(raw).get_file().get_basename()
		_set_status("Saved slot '%s'." % stored)
		_slot_input.text = ""
	else:
		_set_status("Could not save: %s" % SaveManager.get_last_error())


func _set_status(message: String) -> void:
	_status_label.text = message


## --- Routes ------------------------------------------------------------------

func _on_resume_pressed() -> void:
	route_requested.emit(ROUTE_RESUME)


func _on_load_pressed() -> void:
	_close_embedded()
	route_requested.emit(ROUTE_LOAD)


func _on_options_pressed() -> void:
	_embed_screen(OPTIONS_SCENE)


func _on_mods_pressed() -> void:
	_embed_screen(MODS_SCENE)


## Keep the live game loaded: instance the existing screen inside PanelHost and
## redirect its Back button to the pause menu instead of the Main Menu.
func _embed_screen(path: String) -> void:
	_close_embedded()
	var packed := load(path) as PackedScene
	if packed == null:
		_set_status("Could not open %s." % path.get_file())
		return
	var screen: Node = packed.instantiate()
	_panel_host.add_child(screen)
	_embedded = screen
	_box.visible = false
	_panel_host.visible = true
	if screen.has_method("set_back_action"):
		screen.call("set_back_action", Callable(self, "_on_embedded_back"))
	else:
		push_warning("[PauseMenu] embedded screen '%s' has no back_action seam" % path)


func _on_embedded_back() -> void:
	_close_embedded()
	_box.visible = true
	_panel_host.visible = false
	_resume_button.grab_focus()


func _close_embedded() -> void:
	if _embedded != null and is_instance_valid(_embedded):
		_panel_host.remove_child(_embedded)
		_embedded.queue_free()
	_embedded = null
	_panel_host.visible = false
	_box.visible = true


## Stable seam for headless verification of the embedded panel.
func get_embedded_screen_name() -> String:
	return _embedded.name if _embedded != null and is_instance_valid(_embedded) else ""
