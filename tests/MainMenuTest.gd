## MainMenuTest
##
## Persistent headless acceptance harness for ticket 026. Drives the real
## GameManager routes through the menu buttons and asserts external behavior
## only: main-scene setting, the five buttons, a one-shot Quit seam, New Game's
## fresh debug day (day/state/map/player template), each placeholder route and
## its Back button, and the untouched DebugStart launch path used by the v1
## harness. Prints ALL_026_CHECKS_PASSED only when every assertion passed.
extends Node

const EXPECTED_CHECKS: int = 22

var _passed: int = 0
var _failed: int = 0
var _quit_calls: int = 0


func _ready() -> void:
	call_deferred("_run")


func _record_quit() -> void:
	_quit_calls += 1


func _run() -> void:
	await _settle()

	# --- Entry point and routing surface --------------------------------------
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/MainMenu.tscn",
		"T1: MainMenu is the configured run/main_scene")
	_check(
		GameManager.SCENE_MAIN_MENU == "res://scenes/MainMenu.tscn"
		and GameManager.SCENE_LOAD_GAME == "res://scenes/LoadGame.tscn"
		and GameManager.SCENE_OPTIONS == "res://scenes/Options.tscn"
		and GameManager.SCENE_MODS_MENU == "res://scenes/ModsMenu.tscn"
		and GameManager.SCENE_GAME == "res://scenes/Game.tscn",
		"T2: GameManager exposes named routes for every menu and Game")

	GameManager.show_main_menu()
	await _settle()
	var menu: Control = get_tree().current_scene as Control
	_check(menu != null and menu.name == "MainMenu",
		"T3: show_main_menu() enters MainMenu.tscn")

	var expected_buttons: Array = [
		["NewGameButton", "New Game"],
		["LoadGameButton", "Load Game"],
		["OptionsButton", "Options"],
		["ModsButton", "Mods Menu"],
		["QuitButton", "Quit"],
	]
	var buttons_ok: bool = menu != null
	if buttons_ok:
		for entry in expected_buttons:
			var button := menu.get_node_or_null("CenterBox/%s" % entry[0]) as Button
			if button == null or button.text != entry[1]:
				buttons_ok = false
	_check(buttons_ok, "T4: all five buttons exist with the expected labels")

	if menu == null:
		_finish()
		return

	# --- Quit is observable without exiting the harness -----------------------
	menu.set_quit_action(Callable(self, "_record_quit"))
	var quit_button := menu.get_node_or_null("CenterBox/QuitButton") as Button
	if quit_button != null:
		quit_button.pressed.emit()
	_check(_quit_calls == 1, "T5: Quit presses its action exactly once")

	# --- A repeated press in one frame must not queue a second swap -----------
	var swaps_before: int = GameManager.scene_change_count
	var load_button := menu.get_node_or_null("CenterBox/LoadGameButton") as Button
	if load_button != null:
		load_button.pressed.emit()
		load_button.pressed.emit()
	await _settle()
	var double_press_scene: Node = get_tree().current_scene
	_check(GameManager.scene_change_count == swaps_before + 1
		and double_press_scene != null and double_press_scene.name == "LoadGame",
		"T5b: a repeated press starts exactly one scene swap")
	if double_press_scene != null:
		var back_from_double := double_press_scene.get_node_or_null("CenterBox/BackButton") as Button
		if back_from_double != null:
			back_from_double.pressed.emit()
	await _settle()
	# The first MainMenu instance was freed by that detour; re-acquire the live one.
	menu = get_tree().current_scene as Control

	# --- New Game starts the shipped debug day through the v1 path ------------
	var new_game_button := menu.get_node_or_null("CenterBox/NewGameButton") as Button
	if new_game_button != null:
		new_game_button.pressed.emit()
	await _settle()
	var game: Node = get_tree().current_scene
	_check(game != null and game.name == "Game",
		"T6: New Game enters Game.tscn")
	if game == null:
		_finish()
		return

	_check(GameManager.current_save == null,
		"T7: New Game clears the current save (fresh-start path)")
	_check(TimeManager.get_day_number() == 1 and TimeManager.get_state_name() == "PERIOD1",
		"T8: New Game starts day 1 at PERIOD1")
	var renderer := game.get_node_or_null("MapRenderer") as MapRenderer
	_check(renderer != null and renderer.map != null and renderer.map.id == "map:school_debug_large",
		"T9: New Game uses the shipped large debug map")
	var player_instance: NpcInstance = game.get("_player_instance") as NpcInstance
	_check(player_instance != null and player_instance.template_id == "char:alex"
		and game.get_node_or_null("Player") != null,
		"T10: New Game uses the shipped char:alex player template")

	# --- Placeholder routes and Back navigation -------------------------------
	# New Game left us in the playable day; return to the menu to press its buttons.
	GameManager.show_main_menu()
	await _settle()
	var routes: Array = [
		["LoadGameButton", "LoadGame", "Load Game"],
		["OptionsButton", "Options", "Options"],
		["ModsButton", "ModsMenu", "Mods Menu"],
	]
	for route in routes:
		var menu_screen: Control = get_tree().current_scene as Control
		var button: Button = null
		if menu_screen != null:
			button = menu_screen.get_node_or_null("CenterBox/%s" % route[0]) as Button
		if button != null:
			button.pressed.emit()
		await _settle()
		var screen: Node = get_tree().current_scene
		_check(screen != null and screen.name == str(route[1]),
			"%s button enters %s.tscn without crashing" % [route[0], route[1]])
		var title := screen.get_node_or_null("CenterBox/TitleLabel") as Label
		_check(title != null and title.text == str(route[2]),
			"%s placeholder names the screen" % route[1])
		var back := screen.get_node_or_null("CenterBox/BackButton") as Button
		if back != null:
			back.pressed.emit()
		await _settle()
		_check(get_tree().current_scene != null and get_tree().current_scene.name == "MainMenu",
			"%s Back returns to MainMenu" % route[1])

	# --- v1 harness launch path regression ------------------------------------
	GameManager.change_scene("res://scenes/DebugStart.tscn")
	await _settle()
	var debug_game: Node = get_tree().current_scene
	_check(debug_game != null and debug_game.name == "Game",
		"T20: DebugStart still launches Game.tscn directly")
	_check(GameManager.current_save == null,
		"T21: DebugStart still uses the fresh-start path")
	_check(_passed + _failed == EXPECTED_CHECKS,
		"T22: every planned check ran")

	# --- Exercise the shipped Quit path in the real process -------------------
	# A fresh MainMenu instance has no injected quit_action, so this press flows
	# MainMenu -> GameManager.quit_game() -> get_tree().quit(). The marker is
	# printed before the engine exits; no self-quit is needed afterwards.
	GameManager.show_main_menu()
	await _settle()
	var final_menu: Control = get_tree().current_scene as Control
	var real_quit_pressed: bool = false
	if final_menu != null:
		var real_quit_button := final_menu.get_node_or_null("CenterBox/QuitButton") as Button
		if real_quit_button != null:
			real_quit_button.pressed.emit()
			real_quit_pressed = true
	_finish(real_quit_pressed)


func _settle() -> void:
	# change_scene() defers _do_change_scene, and change_scene_to_file defers
	# again to end of frame. Three idle frames makes scene assertions stable.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("[026] PASS " + label)
	else:
		_failed += 1
		print("[026] FAIL " + label)


func _finish(real_quit_already_pressed: bool = false) -> void:
	print("[026] RESULT passed=%d failed=%d" % [_passed, _failed])
	if _failed == 0:
		print("ALL_026_CHECKS_PASSED")
	else:
		print("SOME_026_CHECKS_FAILED")
	# When the real Quit button already requested exit, let that path do it.
	if not real_quit_already_pressed:
		get_tree().quit(0 if _failed == 0 else 1)
