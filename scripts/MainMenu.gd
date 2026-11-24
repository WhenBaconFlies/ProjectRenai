## MainMenu
##
## Player-facing entry scene (ticket 026). The menu owns no game state: every
## button delegates to a GameManager route, so tickets 027/030/031 can swap in
## real screens without touching this script. `quit_action` is a headless test
## seam mirroring Game.set_npc_initiation_gate() — harnesses inject a fake so a
## Quit press can be observed without terminating the test runner.
extends Control

## Override with a zero-arg Callable to observe Quit in headless verification.
## An invalid Callable falls back to _default_quit().
var quit_action: Callable = Callable()

@onready var _new_game_button: Button = $CenterBox/NewGameButton
@onready var _load_game_button: Button = $CenterBox/LoadGameButton
@onready var _options_button: Button = $CenterBox/OptionsButton
@onready var _mods_button: Button = $CenterBox/ModsButton
@onready var _quit_button: Button = $CenterBox/QuitButton


func _ready() -> void:
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_load_game_button.pressed.connect(_on_load_game_pressed)
	_options_button.pressed.connect(_on_options_pressed)
	_mods_button.pressed.connect(_on_mods_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_new_game_button.grab_focus()


## Install a custom Quit action; invalid callables restore the real exit path.
func set_quit_action(action: Callable) -> void:
	quit_action = action if action.is_valid() else Callable(self, "_default_quit")


func _on_new_game_pressed() -> void:
	# No wizard in v2: the default debug day starts through the v1 fresh path.
	GameManager.start_fresh_day()


func _on_load_game_pressed() -> void:
	GameManager.show_load_game()


func _on_options_pressed() -> void:
	GameManager.show_options()


func _on_mods_pressed() -> void:
	GameManager.show_mods_menu()


func _on_quit_pressed() -> void:
	var action: Callable = quit_action if quit_action.is_valid() else Callable(self, "_default_quit")
	action.call()


func _default_quit() -> void:
	GameManager.quit_game()
