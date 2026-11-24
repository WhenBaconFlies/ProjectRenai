## PlaceholderScreen
##
## Safe, non-crashing stand-in for menu screens whose full implementations land
## in later tickets (027 Load Game, 030 Options, 031 Mods Menu). It states which
## screen will appear here and always offers a route back to the main menu.
## Later tickets can replace the scene's root script without touching
## GameManager's routing seam.
extends Control

## Human-readable name of the screen this placeholder stands in for.
@export var screen_title: String = "Menu"

@onready var _title_label: Label = $CenterBox/TitleLabel
@onready var _note_label: Label = $CenterBox/NoteLabel
@onready var _back_button: Button = $CenterBox/BackButton


func _ready() -> void:
	_title_label.text = screen_title
	_note_label.text = "%s will be available in a later update." % screen_title
	_back_button.pressed.connect(_on_back_pressed)
	_back_button.grab_focus()


func _on_back_pressed() -> void:
	GameManager.show_main_menu()
