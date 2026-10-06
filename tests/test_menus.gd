extends RefCounted
## Title and CharacterSelect menus: either player's fight actions drive them, the choices land
## in MatchConfig, the scenes announce navigation through signals, and MatchConfig.reset()
## restores the defaults. change_scenes is false here so no scene is ever swapped under the
## runner.

const TITLE_PATH := "res://scenes/Title.tscn"
const SELECT_PATH := "res://scenes/CharacterSelect.tscn"


func _spawn(ctx: TestContext, path: String) -> Control:
	var scene: PackedScene = load(path)
	ctx.check(scene != null, "%s loads" % path.get_file())
	if scene == null:
		return null
	var root := scene.instantiate() as Control
	ctx.check(root != null, "%s root instantiates as Control" % path.get_file())
	if root == null:
		return null
	root.set("change_scenes", false)
	ctx.add(root)
	return root


## Hold an action for exactly one physics frame.
func _tap(ctx: TestContext, action: String) -> void:
	ctx.press(action)
	await ctx.step(1)
	ctx.release(action)
	await ctx.step(1)


func test_title_instantiates_with_menu_and_wordmark(ctx: TestContext) -> void:
	var title := _spawn(ctx, TITLE_PATH)
	if title == null:
		return
	await ctx.step(1)
	var wordmark := title.get_node_or_null("Wordmark") as Label
	ctx.check(wordmark != null and wordmark.text == "BRAWLCRYPT", "Wordmark reads BRAWLCRYPT")
	var subtitle := title.get_node_or_null("Subtitle") as Label
	ctx.check(
		subtitle != null and subtitle.text == "Local multiplayer platform fighter",
		"Subtitle reads the tagline"
	)
	for item in ["Versus", "VersusCpu", "Controls"]:
		ctx.check(title.get_node_or_null("Menu/" + item) is Label, "Menu has %s" % item)
	var panel := title.get_node_or_null("ControlsPanel") as Control
	ctx.check(panel != null and not panel.visible, "ControlsPanel starts hidden")


func test_title_down_then_attack_picks_versus_cpu(ctx: TestContext) -> void:
	MatchConfig.reset()
	var title := _spawn(ctx, TITLE_PATH)
	if title == null:
		return
	var navigated: Array[String] = []
	title.connect("navigate", func(path: String) -> void: navigated.append(path))
	await ctx.step(1)
	await _tap(ctx, "p1_down")
	ctx.check(navigated.is_empty(), "moving the cursor does not navigate")
	await _tap(ctx, "p1_attack")
	ctx.check(MatchConfig.p2_is_cpu, "Versus CPU sets MatchConfig.p2_is_cpu")
	ctx.check(
		navigated.size() == 1 and navigated[0] == SELECT_PATH,
		"navigate emitted once with the CharacterSelect path (got %s)" % [navigated]
	)
	MatchConfig.reset()


func test_title_p2_actions_drive_the_menu(ctx: TestContext) -> void:
	MatchConfig.reset()
	var title := _spawn(ctx, TITLE_PATH)
	if title == null:
		return
	var navigated: Array[String] = []
	title.connect("navigate", func(path: String) -> void: navigated.append(path))
	await ctx.step(1)
	# Down twice lands on Controls, jump (up) brings it back to Versus CPU. If down were
	# ignored the cursor would still be on Versus (p2_is_cpu stays false); if jump were
	# ignored it would open the Controls panel (nothing navigates).
	await _tap(ctx, "p2_down")
	await _tap(ctx, "p2_down")
	await _tap(ctx, "p2_jump")
	await _tap(ctx, "p2_attack")
	ctx.check(MatchConfig.p2_is_cpu, "P2's down, down, up, attack picks Versus CPU")
	ctx.check(
		navigated.size() == 1 and navigated[0] == SELECT_PATH, "P2's attack confirms the menu"
	)
	MatchConfig.reset()


func test_title_simultaneous_confirms_navigate_once(ctx: TestContext) -> void:
	MatchConfig.reset()
	var title := _spawn(ctx, TITLE_PATH)
	if title == null:
		return
	var navigated: Array[String] = []
	title.connect("navigate", func(path: String) -> void: navigated.append(path))
	await ctx.step(1)
	ctx.press("p1_attack")
	ctx.press("p2_attack")
	await ctx.step(1)
	ctx.release("p1_attack")
	ctx.release("p2_attack")
	await ctx.step(1)
	ctx.check(navigated.size() == 1, "both players confirming on one frame navigates once")


func test_title_controls_panel_toggles_and_swallows_navigation(ctx: TestContext) -> void:
	var title := _spawn(ctx, TITLE_PATH)
	if title == null:
		return
	var navigated: Array[String] = []
	title.connect("navigate", func(path: String) -> void: navigated.append(path))
	await ctx.step(1)
	# Up from the first item wraps to the last: Controls.
	await _tap(ctx, "p1_jump")
	await _tap(ctx, "p1_attack")
	var panel := title.get_node("ControlsPanel") as Control
	ctx.check(panel.visible, "Controls opens the panel")
	var p1_keys := panel.get_node_or_null("P1Keys") as Label
	var p2_keys := panel.get_node_or_null("P2Keys") as Label
	ctx.check(p1_keys != null and p1_keys.text == "A / D\nW\nS\nG", "P1 keys list A / D, W, S, G")
	ctx.check(
		p2_keys != null and p2_keys.text == "Left / Right\nUp\nDown\nL",
		"P2 keys list the arrows and L"
	)
	await _tap(ctx, "p1_down")
	await _tap(ctx, "p1_attack")
	ctx.check(not panel.visible, "attack closes the panel")
	await _tap(ctx, "p1_attack")
	ctx.check(panel.visible, "the cursor stayed on Controls while the panel was open")
	ctx.check(navigated.is_empty(), "nothing navigated while the panel was open")


func test_character_select_cycles_and_starts_when_both_lock_in(ctx: TestContext) -> void:
	MatchConfig.reset()
	var select := _spawn(ctx, SELECT_PATH)
	if select == null:
		return
	var starts: Array[int] = []
	select.connect("start_requested", func() -> void: starts.append(1))
	await ctx.step(1)
	ctx.check(select.call("selected_id", 1) == "kage", "P1 starts on kage")
	ctx.check(select.call("selected_id", 2) == "ignis", "P2 starts on ignis")
	await _tap(ctx, "p1_right")
	ctx.check(select.call("selected_id", 1) == "ignis", "p1_right cycles P1 to ignis")
	await _tap(ctx, "p2_left")
	ctx.check(select.call("selected_id", 2) == "kage", "p2_left cycles P2 to kage")
	var p1_name := select.get_node("P1Column/Name") as Label
	ctx.check(p1_name.text == "Ignis", "P1 column shows Ignis")
	await _tap(ctx, "p1_attack")
	ctx.check(select.call("is_confirmed", 1), "p1_attack locks P1 in")
	ctx.check(starts.is_empty(), "one player locked in does not start the match")
	await _tap(ctx, "p1_right")
	ctx.check(select.call("selected_id", 1) == "ignis", "a locked-in player cannot cycle")
	await _tap(ctx, "p2_attack")
	ctx.check(starts.size() == 1, "both locked in emits start_requested once")
	ctx.check(MatchConfig.p1_character == "ignis", "MatchConfig.p1_character is ignis")
	ctx.check(MatchConfig.p2_character == "kage", "MatchConfig.p2_character is kage")
	ctx.check((select.get_node("FightFlash") as Control).visible, "FIGHT flash is showing")
	ctx.check(not MatchConfig.p2_is_cpu, "two-player mode leaves p2_is_cpu false")
	MatchConfig.reset()


func test_character_select_cpu_mode_starts_on_p1_lock_in(ctx: TestContext) -> void:
	MatchConfig.reset()
	MatchConfig.p2_is_cpu = true
	var select := _spawn(ctx, SELECT_PATH)
	if select == null:
		MatchConfig.reset()
		return
	var starts: Array[int] = []
	select.connect("start_requested", func() -> void: starts.append(1))
	await ctx.step(1)
	await _tap(ctx, "p2_left")
	ctx.check(select.call("selected_id", 2) == "ignis", "P2 input is ignored for a CPU opponent")
	await _tap(ctx, "p1_right")
	ctx.check(select.call("selected_id", 2) == "zephyr", "the CPU takes the fighter after P1's")
	var header := select.get_node("P2Column/Header") as Label
	ctx.check(header.text == "CPU opponent", "P2 column is headed CPU opponent")
	await _tap(ctx, "p1_attack")
	ctx.check(starts.size() == 1, "P1 locking in starts the match against the CPU")
	ctx.check(
		MatchConfig.p1_character == "ignis" and MatchConfig.p2_character == "zephyr",
		"MatchConfig holds ignis vs zephyr"
	)
	MatchConfig.reset()


func test_character_select_ignores_a_key_still_held_from_the_title(ctx: TestContext) -> void:
	# Confirming "Versus CPU" on the title leaves attack held while the select appears; that
	# press must not lock Player 1 in (which in CPU mode would start the match at once).
	MatchConfig.reset()
	MatchConfig.p2_is_cpu = true
	ctx.press("p1_attack")
	var select := _spawn(ctx, SELECT_PATH)
	if select == null:
		MatchConfig.reset()
		return
	var starts: Array[int] = []
	select.connect("start_requested", func() -> void: starts.append(1))
	await ctx.step(5)
	ctx.check(not select.call("is_confirmed", 1), "a held attack does not lock in on arrival")
	ctx.check(starts.is_empty(), "a held attack does not start the match on arrival")
	ctx.release("p1_attack")
	await ctx.step(1)
	await _tap(ctx, "p1_attack")
	ctx.check(starts.size() == 1, "a fresh attack press after release starts the match")
	MatchConfig.reset()


func test_character_select_p1_down_goes_back_to_title(ctx: TestContext) -> void:
	MatchConfig.reset()
	var select := _spawn(ctx, SELECT_PATH)
	if select == null:
		return
	var navigated: Array[String] = []
	select.connect("navigate", func(path: String) -> void: navigated.append(path))
	await ctx.step(1)
	await _tap(ctx, "p1_attack")
	await _tap(ctx, "p1_down")
	ctx.check(not select.call("is_confirmed", 1), "down unlocks a locked-in player")
	ctx.check(navigated.is_empty(), "unlocking does not leave the screen")
	await _tap(ctx, "p1_down")
	ctx.check(
		navigated.size() == 1 and navigated[0] == TITLE_PATH,
		"p1_down with nothing locked goes back to the title"
	)


func test_zephyr_uses_the_placeholder_portrait(ctx: TestContext) -> void:
	MatchConfig.reset()
	MatchConfig.p1_character = "zephyr"
	var select := _spawn(ctx, SELECT_PATH)
	if select == null:
		MatchConfig.reset()
		return
	await ctx.step(1)
	ctx.check(select.call("selected_id", 1) == "zephyr", "the select opens on MatchConfig's pick")
	ctx.check(
		not (select.get_node("P1Column/Portrait") as Control).visible,
		"no TextureRect portrait for zephyr"
	)
	ctx.check(
		(select.get_node("P1Column/PortraitPlaceholder") as Control).visible,
		"placeholder disc shown for zephyr"
	)
	ctx.check(
		(select.get_node("P2Column/Portrait") as TextureRect).texture != null,
		"ignis keeps its painted portrait"
	)
	MatchConfig.reset()


func test_match_config_reset_restores_defaults(ctx: TestContext) -> void:
	MatchConfig.p1_character = "zephyr"
	MatchConfig.p2_character = "kage"
	MatchConfig.p2_is_cpu = true
	MatchConfig.difficulty = 2
	MatchConfig.stocks = 5
	MatchConfig.reset()
	ctx.check(MatchConfig.p1_character == "kage", "reset: p1_character kage")
	ctx.check(MatchConfig.p2_character == "ignis", "reset: p2_character ignis")
	ctx.check(not MatchConfig.p2_is_cpu, "reset: p2_is_cpu false")
	ctx.check(MatchConfig.difficulty == 1, "reset: difficulty 1")
	ctx.check(MatchConfig.stocks == 3, "reset: stocks 3")
	await ctx.step(1)


func test_roster_ids_and_defs(ctx: TestContext) -> void:
	var want_ids: Array[String] = ["kage", "ignis", "zephyr"]
	ctx.check(Roster.ids() == want_ids, "roster order is kage, ignis, zephyr")
	var ignis := Roster.get_def("ignis")
	ctx.check(ignis["title"] == "The Spectral Dreadnought", "Ignis title")
	ctx.check(
		(
			ignis["speed"] == 5
			and ignis["power"] == 9
			and ignis["defense"] == 9
			and ignis["recovery"] == 5
		),
		"Ignis stats 5/9/9/5"
	)
	var kage := Roster.get_def("kage")
	ctx.check(kage["speed"] == 9 and kage["recovery"] == 9, "Kage speed and recovery 9")
	ctx.check(Roster.get_def("zephyr")["recovery"] == 10, "Zephyr recovery 10")
	await ctx.step(1)
