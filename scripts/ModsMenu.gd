## ModsMenu
##
## Player-facing Mods Menu for ticket 031. Lists every discovered mod from both
## scan roots with manifest metadata and load status, and offers a per-mod
## enable/disable toggle backed by SettingsManager. Toggling never rescans live:
## the load-status column reflects the current session and a restart notice is
## shown, because ModLoader applies settings flags on the next launch (029).
##
## The screen keeps PlaceholderScreen's `back_action` seam so the ticket-028
## pause overlay can embed it in place and route Back back to pause.
extends Control

## Human-readable name of the screen (kept for parity with placeholder screens).
@export var screen_title: String = "Mods Menu"

## Injected by the pause overlay; an invalid/absent callable routes to Main Menu.
var back_action: Callable = Callable()

const ROW_PREFIX: String = "ModRow_"
const RESTART_TEXT: String = "Restart required: mod changes take effect on next launch."

@onready var _title_label: Label = $TitleLabel
@onready var _mod_box: VBoxContainer = $ModScroll/ModBox
@onready var _restart_notice: Label = $RestartNotice
@onready var _back_button: Button = $BackButton

## Ordered copy of the loader snapshot used to build and address the rows.
var _mods: Array = []


func _ready() -> void:
	_title_label.text = screen_title
	_populate()
	# The snapshot is frozen at load time; settings are the live source of truth.
	# Show the notice on entry when they disagree, so Back + reopen cannot hide a
	# pending restart (the pause overlay re-instances this screen on every open).
	_restart_notice.text = RESTART_TEXT
	_restart_notice.visible = _has_pending_restart()
	_back_button.pressed.connect(_on_back_pressed)
	_back_button.grab_focus()


## --- Population -------------------------------------------------------------

func _populate() -> void:
	_mods = ModLoader.get_installed_mods()
	for child in _mod_box.get_children():
		_mod_box.remove_child(child)
		child.queue_free()
	for i in _mods.size():
		_mod_box.add_child(_make_row(i, _mods[i] as Dictionary))


## Build one stable-named row. Node names are fixed so headless harnesses (and
## future UI passes) can address rows without reaching into private state.
func _make_row(index: int, entry: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.name = "%s%d" % [ROW_PREFIX, index]
	row.set("theme_override_constants/separation", 2)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var display_name: String = str(entry.get("name", ""))
	if display_name.is_empty():
		display_name = str(entry.get("id", ""))
	var mod_id: String = str(entry.get("id", ""))
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = "%s  [%s]" % [display_name, mod_id]
	row.add_child(name_label)

	var meta_label := Label.new()
	meta_label.name = "MetaLabel"
	var deps: Array = entry.get("dependencies", [])
	var deps_text: String = "none"
	if not deps.is_empty():
		var parts: PackedStringArray = PackedStringArray()
		for dep in deps:
			parts.append(str(dep))
		deps_text = ", ".join(parts)
	meta_label.text = "Version: %s | Author: %s | Depends: %s | Root: %s" % [
		str(entry.get("version", "")),
		str(entry.get("author", "")),
		deps_text,
		str(entry.get("root", "")),
	]
	row.add_child(meta_label)

	var status_label := Label.new()
	status_label.name = "StatusLabel"
	var status: String = str(entry.get("status", "skipped"))
	var reason: String = str(entry.get("reason", ""))
	status_label.text = "Loaded" if status == "loaded" else "Skipped — %s" % reason
	row.add_child(status_label)

	var toggle := CheckButton.new()
	toggle.name = "ToggleButton"
	toggle.text = "Enabled"
	var togglable: bool = bool(entry.get("togglable", false))
	# Use the live setting and the effective (author-aware) state, not the frozen
	# snapshot flag: an author-hard-disabled or invalid mod must read as off.
	toggle.button_pressed = togglable and SettingsManager.get_mod_enabled(mod_id)
	toggle.disabled = not togglable
	toggle.toggled.connect(Callable(self, "_on_toggle").bind(index))
	row.add_child(toggle)

	return row


## True when a player toggle has not yet been applied by a restart: the live
## settings flag differs from what the loader saw on the last launch.
func _has_pending_restart() -> bool:
	for entry_variant in _mods:
		var entry: Dictionary = entry_variant
		if not bool(entry.get("togglable", false)):
			continue
		var mod_id: String = str(entry.get("id", ""))
		if mod_id.is_empty():
			continue
		if SettingsManager.get_mod_enabled(mod_id) != bool(entry.get("settings_enabled", true)):
			return true
	return false


## Signal payload is (pressed, index) because the index is bound at row build.
func _on_toggle(pressed: bool, index: int) -> void:
	if index < 0 or index >= _mods.size():
		return
	var entry: Dictionary = _mods[index]
	var mod_id: String = str(entry.get("id", ""))
	if mod_id.is_empty() or not bool(entry.get("togglable", false)):
		return
	# Disable writes an explicit false; enable removes the flag so the 025
	# "no flag = enabled" default applies again.
	if pressed:
		SettingsManager.clear_mod_flag(mod_id)
	else:
		SettingsManager.set_mod_enabled(mod_id, false)
	entry["settings_enabled"] = pressed
	# No load_mods() call and no status refresh: the change applies next launch.
	_restart_notice.visible = true


## --- Back seam --------------------------------------------------------------

## Accepts an injected action (used by the pause overlay). An invalid callable
## restores the normal Main Menu route.
func set_back_action(action: Callable) -> void:
	back_action = action if action.is_valid() else Callable(self, "_default_back")


func _on_back_pressed() -> void:
	var action: Callable = back_action if back_action.is_valid() else Callable(self, "_default_back")
	action.call()


func _default_back() -> void:
	GameManager.show_main_menu()
