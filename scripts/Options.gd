## Options
##
## Player-facing Options screen for ticket 030. Exposes Volume, Chunk tier radii
## and tick rates, Resolution (windowed presets + fullscreen) and a Language
## display. Every control writes through SettingsManager, so changes persist to
## `user://settings.cfg` and apply immediately where the engine allows it.
## Display changes are applied immediately, so there is no restart notice. The
## relationship-feedback toggle is deliberately absent (it stays a save-only/debug flag).
##
## The screen keeps PlaceholderScreen's `back_action` seam so the ticket-028
## pause overlay can embed it in place and route Back back to pause.
extends Control

## Human-readable name of the screen (kept for parity with placeholder screens).
@export var screen_title: String = "Options"

## Injected by the pause overlay; an invalid/absent callable routes to Main Menu.
var back_action: Callable = Callable()

@onready var _title_label: Label = $TitleLabel
@onready var _volume_slider: HSlider = $SettingsScroll/SettingsBox/VolumeRow/VolumeSlider
@onready var _volume_value_label: Label = $SettingsScroll/SettingsBox/VolumeRow/VolumeValueLabel
@onready var _close_radius_spin: SpinBox = $SettingsScroll/SettingsBox/CloseRadiusRow/CloseRadiusSpin
@onready var _near_radius_spin: SpinBox = $SettingsScroll/SettingsBox/NearRadiusRow/NearRadiusSpin
@onready var _close_tick_spin: SpinBox = $SettingsScroll/SettingsBox/CloseTickRow/CloseTickSpin
@onready var _near_tick_spin: SpinBox = $SettingsScroll/SettingsBox/NearTickRow/NearTickSpin
@onready var _far_tick_spin: SpinBox = $SettingsScroll/SettingsBox/FarTickRow/FarTickSpin
@onready var _resolution_option: OptionButton = $SettingsScroll/SettingsBox/ResolutionRow/ResolutionOption
@onready var _fullscreen_check: CheckButton = $SettingsScroll/SettingsBox/FullscreenRow/FullscreenCheck
@onready var _language_option: OptionButton = $SettingsScroll/SettingsBox/LanguageRow/LanguageOption
@onready var _back_button: Button = $BackButton

## Suppresses write-back while controls are being initialised from stored values.
var _populating: bool = false


func _ready() -> void:
	_title_label.text = screen_title
	_populate()
	_connect_controls()
	_back_button.pressed.connect(_on_back_pressed)
	_back_button.grab_focus()


## --- Population -------------------------------------------------------------

func _populate() -> void:
	_populating = true

	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 100.0
	_volume_slider.step = 1.0
	_volume_slider.value = SettingsManager.get_master_volume() * 100.0
	_update_volume_label()

	# ChunkManager silently clamps near up to close; mirror that here so the UI
	# never shows a near radius the simulation will not actually use.
	var close_value: int = SettingsManager.get_close_radius_chunks()
	var near_value: int = maxi(SettingsManager.get_near_radius_chunks(), close_value)
	_configure_int_spin(_close_radius_spin, 0, 32, close_value)
	_configure_int_spin(_near_radius_spin, maxi(1, close_value), 64, near_value)
	_configure_float_spin(_close_tick_spin, 0.0, 30.0, SettingsManager.get_close_tick_sec())
	_configure_float_spin(_near_tick_spin, 0.0, 30.0, SettingsManager.get_near_tick_sec())
	_configure_float_spin(_far_tick_spin, 0.0, 120.0, SettingsManager.get_far_tick_sec())

	_resolution_option.clear()
	for preset in SettingsManager.get_resolution_presets():
		_resolution_option.add_item(str((preset as Dictionary)["label"]))
	var preset_index: int = SettingsManager.get_resolution_preset_index()
	if preset_index >= 0:
		_resolution_option.select(preset_index)
	else:
		_resolution_option.selected = -1
	_fullscreen_check.button_pressed = SettingsManager.get_fullscreen()

	_language_option.clear()
	for language in SettingsManager.get_supported_languages():
		_language_option.add_item(str(language))
	if _language_option.item_count > 0:
		_language_option.select(0)
	_language_option.disabled = true

	_populating = false


func _configure_int_spin(spin: SpinBox, minimum: int, maximum: int, value: int) -> void:
	spin.min_value = float(minimum)
	spin.max_value = float(maximum)
	spin.step = 1.0
	spin.rounded = true
	spin.value = float(value)


func _configure_float_spin(spin: SpinBox, minimum: float, maximum: float, value: float) -> void:
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 0.05
	spin.rounded = false
	spin.value = value


func _update_volume_label() -> void:
	_volume_value_label.text = "%d%%" % int(round(_volume_slider.value))


## --- Control wiring ---------------------------------------------------------

func _connect_controls() -> void:
	# value_changed only updates the readout while dragging; the write (and its
	# ConfigFile save) happens once on drag commit so a drag is not N disk writes.
	_volume_slider.value_changed.connect(_on_volume_value_changed)
	_volume_slider.drag_ended.connect(_on_volume_drag_ended)
	_close_radius_spin.value_changed.connect(_on_close_radius_changed)
	_near_radius_spin.value_changed.connect(_on_near_radius_changed)
	_close_tick_spin.value_changed.connect(_on_close_tick_changed)
	_near_tick_spin.value_changed.connect(_on_near_tick_changed)
	_far_tick_spin.value_changed.connect(_on_far_tick_changed)
	_resolution_option.item_selected.connect(_on_resolution_selected)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)


func _on_volume_value_changed(_value: float) -> void:
	# Live readout only; no settings write until the drag is released.
	_update_volume_label()


func _on_volume_drag_ended(_changed: bool) -> void:
	if _populating:
		return
	SettingsManager.set_master_volume(_volume_slider.value / 100.0)


func _on_close_radius_changed(value: float) -> void:
	_write_chunk_int("close_radius_chunks", value)
	# Keep the near radius at least as large as close, matching ChunkManager's
	# runtime clamp, and persist the raised value through the normal signal path.
	var close_value: int = int(round(value))
	_near_radius_spin.min_value = float(maxi(1, close_value))
	if int(round(_near_radius_spin.value)) < close_value:
		_near_radius_spin.value = float(close_value)


func _on_near_radius_changed(value: float) -> void:
	_write_chunk_int("near_radius_chunks", value)


func _on_close_tick_changed(value: float) -> void:
	_write_chunk_float("close_tick_sec", value)


func _on_near_tick_changed(value: float) -> void:
	_write_chunk_float("near_tick_sec", value)


func _on_far_tick_changed(value: float) -> void:
	_write_chunk_float("far_tick_sec", value)


func _write_chunk_int(key: String, value: float) -> void:
	if _populating:
		return
	SettingsManager.set_chunk_value(key, int(round(value)))


func _write_chunk_float(key: String, value: float) -> void:
	if _populating:
		return
	SettingsManager.set_chunk_value(key, value)


func _on_resolution_selected(index: int) -> void:
	if _populating:
		return
	SettingsManager.set_resolution_preset(index)


func _on_fullscreen_toggled(pressed: bool) -> void:
	if _populating:
		return
	SettingsManager.set_fullscreen(pressed)


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
