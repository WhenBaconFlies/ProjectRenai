class_name DialoguePoolUI
extends Control

## DialoguePoolUI
##
## Minimal data-driven selector for the dialogue pool (ticket 014). Given the
## topics chosen by DialogueFilter it builds one button per topic plus Cancel;
## number keys 1–5, Esc and mouse clicks are all accepted. It owns no game state
## beyond whether it is open — Game.gd locks/unlocks the world and owns the
## conversation.


## A topic was picked. Ticket 015 resolves this signal; 014 applies no deltas.
signal topic_selected(topic: DialogueTopic, initiator_id: String, target_id: String)

## The player cancelled (Cancel button / Esc), or no topics were eligible and
## the fallback message was dismissed.
signal cancelled


var _panel: PanelContainer = null
var _header: Label = null
var _message: Label = null
var _list: VBoxContainer = null
var _buttons: Array[Button] = []

var _topics: Array = []
var _initiator_id: String = ""
var _target_id: String = ""
var _is_open: bool = false


func _ready() -> void:
	# Full-rect root with IGNORE so only the centred panel catches mouse input.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -220.0
	_panel.offset_top = -160.0
	_panel.offset_right = 220.0
	_panel.offset_bottom = 160.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.16, 0.94)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_child(_list)

	_header = Label.new()
	_header.text = "Choose a topic"
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(_header)

	_message = Label.new()
	_message.text = "No appropriate topics right now."
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.visible = false
	_list.add_child(_message)

	hide_pool()


func is_open() -> bool:
	return _is_open


## Show up to five topic buttons plus Cancel. Number keys map to button order.
func show_pool(topics: Array, initiator_id: String, target_id: String) -> void:
	_clear_buttons()
	_topics = topics.duplicate()
	_initiator_id = initiator_id
	_target_id = target_id
	_is_open = true
	_header.text = "Choose a topic"
	_message.visible = false

	for i in range(_topics.size()):
		var topic: DialogueTopic = _topics[i] as DialogueTopic
		if topic == null:
			continue
		var button := Button.new()
		button.text = "%d. %s" % [i + 1, topic.text]
		button.pressed.connect(_on_topic_pressed.bind(i))
		_add_button(button)
	_add_cancel_button()
	visible = true


## Graceful fallback: no eligible topics, so offer only a way out.
func show_empty(initiator_id: String, target_id: String) -> void:
	_clear_buttons()
	_topics = []
	_initiator_id = initiator_id
	_target_id = target_id
	_is_open = true
	_header.text = "Conversation"
	_message.text = "No appropriate topics right now."
	_message.visible = true
	_add_cancel_button()
	visible = true


func hide_pool() -> void:
	_clear_buttons()
	_topics = []
	_is_open = false
	visible = false


func _add_cancel_button() -> void:
	var cancel := Button.new()
	cancel.text = "Cancel (Esc)"
	cancel.pressed.connect(cancel_conversation)
	_add_button(cancel)


func _add_button(button: Button) -> void:
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(button)
	_buttons.append(button)


func _clear_buttons() -> void:
	for button in _buttons:
		if is_instance_valid(button):
			button.queue_free()
	_buttons.clear()


func _on_topic_pressed(index: int) -> void:
	if not _is_open or index < 0 or index >= _topics.size():
		return
	var topic: DialogueTopic = _topics[index] as DialogueTopic
	if topic == null:
		return
	# Capture ids before hide_pool() clears state.
	var initiator_id: String = _initiator_id
	var target_id: String = _target_id
	hide_pool()
	topic_selected.emit(topic, initiator_id, target_id)


func cancel_conversation() -> void:
	if not _is_open:
		return
	hide_pool()
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if not event.is_pressed():
		return
	if event.is_action_pressed("ui_cancel"):
		cancel_conversation()
		return
	var key := event as InputEventKey
	if key == null or key.echo:
		return
	if key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_5:
		_on_topic_pressed(int(key.physical_keycode) - int(KEY_1))
