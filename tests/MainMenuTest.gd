## MainMenuTest
##
## Persistent headless acceptance harness for ticket 026. Drives the real
## GameManager routes through the menu buttons and asserts external behavior
## only: main-scene setting, the five buttons, a one-shot Quit seam, New Game's
## fresh debug day (day/state/map/player template), each placeholder route and
## its Back button, and the untouched DebugStart launch path used by the v1
## harness. Prints ALL_026_CHECKS_PASSED only when every assertion passed.
extends Node

const EXPECTED_CHECKS: int = 21

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
	var routes: Array = [
		["show_load_game", "LoadGame", "Load Game"],
		["show_options", "Options", "Options"],
		["show_mods_menu", "ModsMenu", "Mods Menu"],
	]
	for route in routes:
		GameManager.call(str(route[0]))
		await _settle()
		var screen: Node = get_tree().current_scene
		_check(screen != null and screen.name == str(route[1]),
			"Route %s enters %s.tscn without crashing" % [route[0], route[1]])
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

	# Quit from the menu rather than mid-day.
	GameManager.show_main_menu()
	await _settle()
	_finish()


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


func _finish() -> void:
	print("[026] RESULT passed=%d failed=%d" % [_passed, _failed])
	if _failed == 0:
		print("ALL_026_CHECKS_PASSED")
	else:
		print("SOME_026_CHECKS_FAILED")
	get_tree().quit(0 if _failed == 0 else 1)
