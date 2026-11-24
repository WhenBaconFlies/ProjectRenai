class_name ConversationUI
extends Control

## ConversationUI
##
## World-visible conversation overlay (ticket 024). A semi-transparent panel is
## anchored to the bottom of the viewport so the school keeps rendering behind
## it. It shows the current speaker, the spoken line and a stack of numbered
## choices; two transparent portrait slots are laid out (speaker left, listener
## right) but render no art in v2.
##
## The UI owns no conversation state: Game.gd supplies each line and the choice
## labels, receives `choice_selected(index)` / `cancelled`, and maps the index to
## a conversation action. Number keys, mouse clicks and Esc are accepted.


## A numbered choice was picked (index into the labels passed to show_line).
signal choice_selected(index: int)

## The player pressed Esc (leave/cancel the conversation).
signal cancelled


## Bottom panel geometry. The panel is deliberately shorter than the viewport so
## the world above it remains visible.
const PANEL_TOP_OFFSET: float = -190.0
const PANEL_BOTTOM_OFFSET: float = -16.0
const PANEL_SIDE_MARGIN: float = 16.0
const PORTRAIT_WIDTH: float = 72.0
const PORTRAIT_HEIGHT: float = 96.0

var _panel: PanelContainer = null
var _choices_box: VBoxContainer = null
var _speaker_label: Label = null
var _line_label: Label = null
var _speaker_portrait: PanelContainer = null
var _listener_portrait: PanelContainer = null
var _buttons: Array[Button] = []

var _choices: Array[String] = []
var _is_open: bool = false


func _ready() -> void:
	_build()


## Build lazily so show_line() is safe when called before this node's _ready().
func _build() -> void:
	if _panel != null:
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel.name = "ConversationPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = PANEL_SIDE_MARGIN
	_panel.offset_right = -PANEL_SIDE_MARGIN
	_panel.offset_top = PANEL_TOP_OFFSET
	_panel.offset_bottom = PANEL_BOTTOM_OFFSET
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.16, 0.82)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	_speaker_portrait = _make_portrait_slot("SpeakerPortrait")
	row.add_child(_speaker_portrait)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 6)
	row.add_child(center)

	_speaker_label = Label.new()
	_speaker_label.text = ""
	_speaker_label.add_theme_font_size_override("font_size", 18)
	center.add_child(_speaker_label)

	_line_label = Label.new()
	_line_label.text = ""
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line_label.custom_minimum_size = Vector2(0, 34)
	center.add_child(_line_label)

	_choices_box = VBoxContainer.new()
	_choices_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices_box.add_theme_constant_override("separation", 4)
	center.add_child(_choices_box)

	_listener_portrait = _make_portrait_slot("ListenerPortrait")
	row.add_child(_listener_portrait)

	hide_panel()


## Reserved portrait slot: a fixed-size, fully transparent PanelContainer. No
## TextureRect/Sprite is added — portrait art is an explicit v3 task.
func _make_portrait_slot(node_name: String) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = node_name
	slot.custom_minimum_size = Vector2(PORTRAIT_WIDTH, PORTRAIT_HEIGHT)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var blank := StyleBoxFlat.new()
	blank.bg_color = Color(1, 1, 1, 0)
	slot.add_theme_stylebox_override("panel", blank)
	return slot


func is_open() -> bool:
	return _is_open


## Programmatic leave (mouse/Cancel button equivalent), also handy in headless tests.
func cancel_conversation() -> void:
	if not _is_open:
		return
	cancelled.emit()


## Choice labels currently rendered, in number-key order.
func get_choices() -> Array:
	return _choices.duplicate()


## Render one line and its numbered choices. `listener_name` is reserved for the
## portrait slot's future nameplate; no art is drawn here.
func show_line(speaker_name: String, line: String, choices: Array, listener_name: String = "") -> void:
	_build()
	_clear_buttons()
	_choices.clear()
	for label in choices:
		_choices.append(str(label))
	_speaker_label.text = speaker_name
	_line_label.text = line
	# Keep the slot nodes meaningful for future portrait work without drawing art.
	_speaker_portrait.tooltip_text = speaker_name
	_listener_portrait.tooltip_text = listener_name
	for i in range(_choices.size()):
		var button := Button.new()
		button.text = "%d. %s" % [i + 1, _choices[i]]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_choice_pressed.bind(i))
		_choices_box.add_child(button)
		_buttons.append(button)
	_is_open = true
	visible = true


func hide_panel() -> void:
	_clear_buttons()
	_choices.clear()
	_is_open = false
	visible = false


func _clear_buttons() -> void:
	_buttons.clear()
	if _choices_box != null:
		for child in _choices_box.get_children():
			if is_instance_valid(child):
				child.queue_free()


func _on_choice_pressed(index: int) -> void:
	if not _is_open or index < 0 or index >= _choices.size():
		return
	choice_selected.emit(index)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("ui_cancel"):
		cancelled.emit()
		return
	var key := event as InputEventKey
	if key == null:
		return
	var digit: int = -1
	if key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_9:
		digit = int(key.physical_keycode) - int(KEY_1)
	elif key.keycode >= KEY_1 and key.keycode <= KEY_9:
		digit = int(key.keycode) - int(KEY_1)
	if digit >= 0:
		_on_choice_pressed(digit)
