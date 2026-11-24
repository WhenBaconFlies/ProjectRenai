class_name InteractionFeedbackUI
extends Control

## InteractionFeedbackUI
##
## Small post-interaction feedback panel (ticket 015). Shows the roll outcome
## and both parties' before→after meters, mood and relationship type. It owns no
## game state: Game.gd decides whether to show it and hides it when the feedback
## toggle is off. Auto-dismisses after `display_sec`; clicking the panel also
## dismisses it early.


## Seconds the panel stays visible before auto-dismissing.
@export var display_sec: float = 3.5

var _panel: PanelContainer = null
var _title: Label = null
var _topic: Label = null
var _roll: Label = null
var _initiator_line: Label = null
var _target_line: Label = null
var _hint: Label = null
var _is_open: bool = false

## Guards against an older auto-dismiss timer hiding a newer result.
var _generation: int = 0

## Player-involving results that arrived while a panel was already open. They are
## shown one after another so a concurrent interaction cannot silently replace an
## outcome the player has not read yet.
var _queue: Array = []


func _ready() -> void:
	_build()


## Build the panel lazily so show_result() is safe even when called before the
## node has received _ready() (e.g. from a headless SceneTree verification).
func _build() -> void:
	if _panel != null:
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.anchor_left = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -260.0
	_panel.offset_top = -150.0
	_panel.offset_right = 260.0
	_panel.offset_bottom = -24.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.18, 0.95)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	_panel.add_theme_stylebox_override("panel", style)
	_panel.gui_input.connect(_on_panel_gui_input)
	add_child(_panel)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_child(list)

	_title = _add_label(list, "", HORIZONTAL_ALIGNMENT_CENTER)
	_topic = _add_label(list, "", HORIZONTAL_ALIGNMENT_CENTER)
	_roll = _add_label(list, "", HORIZONTAL_ALIGNMENT_CENTER)
	_initiator_line = _add_label(list, "", HORIZONTAL_ALIGNMENT_LEFT)
	_target_line = _add_label(list, "", HORIZONTAL_ALIGNMENT_LEFT)
	_hint = _add_label(list, "click to dismiss", HORIZONTAL_ALIGNMENT_CENTER)

	hide_feedback()


func _add_label(parent: Node, text: String, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func is_open() -> bool:
	return _is_open


## Queue one resolver result. Names are display strings ("You", "Jordan", ...).
## If a panel is already showing, the new result is displayed when that one closes.
func show_result(result: Dictionary, initiator_name: String, target_name: String) -> void:
	if result.is_empty():
		return
	if _is_open:
		_queue.append({
			"result": result,
			"initiator_name": initiator_name,
			"target_name": target_name,
		})
		return
	_display(result, initiator_name, target_name)


## Render one resolver result immediately.
func _display(result: Dictionary, initiator_name: String, target_name: String) -> void:
	_build()
	var success: bool = bool(result.get("success", false))
	_title.text = "Success!" if success else "Not quite..."
	_topic.text = str(result.get("topic_text", ""))

	var stat_name: String = str(result.get("checked_stat", ""))
	if stat_name.is_empty():
		stat_name = "no stat"
	var roll_text: String = "%s %d + fam %d + die %d = %d  vs  %d" % [
		stat_name,
		int(result.get("stat_bonus", 0)),
		int(result.get("familiarity_bonus", 0)),
		int(result.get("die", 0)),
		int(result.get("roll", 0)),
		int(result.get("effective_difficulty", int(result.get("difficulty", 0)))),
	]
	var margin: int = int(result.get("margin", 0))
	roll_text += "  (margin %+d)" % margin
	_roll.text = roll_text

	var before: Dictionary = result.get("before", {})
	var after: Dictionary = result.get("after", {})
	_initiator_line.text = _party_line(
		initiator_name, before.get("initiator", {}), after.get("initiator", {})
	)
	_target_line.text = _party_line(
		target_name, before.get("target", {}), after.get("target", {})
	)

	_is_open = true
	visible = true
	_generation += 1
	var token: int = _generation
	if is_inside_tree():
		var tree := get_tree()
		if tree != null:
			tree.create_timer(maxf(0.1, display_sec)).timeout.connect(_on_display_timeout.bind(token))


func hide_feedback() -> void:
	_generation += 1
	_is_open = false
	visible = false
	# Explicit hide (e.g. feedback toggled off) discards pending results.
	_queue.clear()


## "You: Fam 0→3  Aff 0→3  Mood 50→52  [Stranger → Acquaintance]"
func _party_line(name: String, before_variant: Variant, after_variant: Variant) -> String:
	var before: Dictionary = before_variant if before_variant is Dictionary else {}
	var after: Dictionary = after_variant if after_variant is Dictionary else {}
	var line: String = "%s:  Fam %d→%d  Aff %d→%d  Mood %d→%d" % [
		name,
		int(before.get("familiarity", 0)),
		int(after.get("familiarity", 0)),
		int(before.get("affection", 0)),
		int(after.get("affection", 0)),
		int(before.get("mood", 0)),
		int(after.get("mood", 0)),
	]
	var old_type: String = str(before.get("relationship", ""))
	var new_type: String = str(after.get("relationship", ""))
	if not old_type.is_empty() and old_type != new_type:
		line += "  [%s → %s]" % [old_type, new_type]
	return line


func _on_display_timeout(token: int) -> void:
	if token == _generation and _is_open:
		_advance()


func _on_panel_gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		_advance()


## Close the current result and show the next queued one, if any.
func _advance() -> void:
	_generation += 1
	_is_open = false
	visible = false
	if _queue.is_empty():
		return
	var next: Dictionary = _queue.pop_front()
	_display(
		next.get("result", {}),
		str(next.get("initiator_name", "")),
		str(next.get("target_name", ""))
	)
