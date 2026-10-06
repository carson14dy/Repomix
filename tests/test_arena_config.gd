extends RefCounted
## The menus' MatchConfig reaches the arena (scenes/Main.tscn): the picked fighters' sprites,
## HUD names and portraits, the stock count, the CPU opponent (prefabs/BotController.tscn
## under Main while p2_is_cpu) and, once the match is over, Down returns to the character
## select. change_scenes is false here so no scene is swapped under the runner; every test
## that writes MatchConfig resets it.

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const SELECT_PATH := "res://scenes/CharacterSelect.tscn"
const BELOW_STAGE := Vector2(640, 1150)
const P2_ACTIONS: Array[String] = ["p2_left", "p2_right", "p2_jump", "p2_down", "p2_attack"]


func _spawn_main(ctx: TestContext) -> Node2D:
	var scene: PackedScene = load(MAIN_SCENE_PATH)
	var main := scene.instantiate() as Node2D
	ctx.check(main != null, "Main.tscn instantiates")
	if main == null:
		return null
	main.set("change_scenes", false)
	ctx.add(main)
	return main


func _release_p2(ctx: TestContext) -> void:
	for action in P2_ACTIONS:
		ctx.release(action)


## The picks are swapped from the scene defaults (Kage / Ignis), so routing both slots to one
## pick, or ignoring the slot, shows up on a sprite, an offset or a medallion.
func test_selected_fighters_reach_the_sprites_and_hud(ctx: TestContext) -> void:
	MatchConfig.reset()
	MatchConfig.p1_character = "ignis"
	MatchConfig.p2_character = "kage"
	var main := _spawn_main(ctx)
	if main == null:
		MatchConfig.reset()
		return
	await ctx.step(1)
	# The sprite node sits at the feet; the art is lifted by half its height (72 / 64 px).
	var rows := [
		["Player1", "P1", "ignis", -36.0, "Ignis", BrawlTheme.P1_COLOR],
		["Player2", "P2", "kage", -32.0, "Kage", BrawlTheme.P2_COLOR],
	]
	for row: Array in rows:
		var sprite := main.get_node("%s/Sprite2D" % row[0]) as Sprite2D
		ctx.check(
			sprite.texture.resource_path.ends_with("%s.png" % row[2]),
			"%s wears the %s sprite" % [row[0], row[4]]
		)
		ctx.check_near(sprite.offset.y, row[3], 0.01, "%s's sprite is re-anchored" % row[0])
		var name_label := main.get_node("HUD/Root/%sMedallion/Name" % row[1]) as Label
		ctx.check(
			name_label.text == row[4],
			"%sMedallion/Name reads %s (got '%s')" % [row[1], row[4], name_label.text]
		)
		ctx.check(
			name_label.get_theme_color("font_color").is_equal_approx(row[5]),
			"%sMedallion/Name keeps the slot's player colour" % row[1]
		)
		var portrait := main.get_node("HUD/Root/%sMedallion/Portrait" % row[1]) as TextureRect
		ctx.check(
			(
				portrait.visible
				and portrait.texture != null
				and portrait.texture.resource_path.ends_with("%s_portrait.png" % row[2])
			),
			"%sMedallion/Portrait shows %s_portrait.png" % [row[1], row[2]]
		)
	MatchConfig.reset()


func test_fighter_without_portrait_gets_the_placeholder_disc(ctx: TestContext) -> void:
	MatchConfig.reset()
	MatchConfig.p1_character = "zephyr"
	var main := _spawn_main(ctx)
	if main == null:
		MatchConfig.reset()
		return
	await ctx.step(1)
	var name_label := main.get_node("HUD/Root/P1Medallion/Name") as Label
	ctx.check(name_label.text == "Zephyr", "P1Medallion/Name reads Zephyr")
	var portrait := main.get_node("HUD/Root/P1Medallion/Portrait") as TextureRect
	ctx.check(not portrait.visible, "Zephyr has no portrait art, so the scene's portrait is hidden")
	var placeholder := main.get_node_or_null("HUD/Root/P1Medallion/PortraitPlaceholder") as Control
	ctx.check(
		(
			placeholder != null
			and placeholder.visible
			and placeholder.get("initial") == "Z"
			and placeholder.position == portrait.position
			and placeholder.size == portrait.size
		),
		"a placeholder disc with the initial Z sits where the portrait was"
	)
	var p2_portrait := main.get_node("HUD/Root/P2Medallion/Portrait") as TextureRect
	ctx.check(
		(
			p2_portrait.visible
			and main.get_node_or_null("HUD/Root/P2Medallion/PortraitPlaceholder") == null
		),
		"Ignis keeps its painted portrait and gets no placeholder"
	)
	MatchConfig.reset()


func test_stocks_follow_match_config(ctx: TestContext) -> void:
	MatchConfig.reset()
	MatchConfig.stocks = 2
	var main := _spawn_main(ctx)
	if main == null:
		MatchConfig.reset()
		return
	await ctx.step(1)
	var match_node: Match = main.get_node("Match")
	ctx.check(
		match_node.stocks[1] == 2 and match_node.stocks[2] == 2,
		"Match hands out MatchConfig.stocks (2) per player (got %s)" % [match_node.stocks]
	)
	var pips := main.get_node("HUD/Root/P2Medallion/Stocks")
	ctx.check(int(pips.get("stocks")) == 2, "P2 stock pips show 2")
	ctx.check(
		int(pips.get("max_stocks")) == 2,
		"the pips draw 2 outlines, not an empty third (got %d)" % int(pips.get("max_stocks"))
	)
	ctx.check(
		main.get_node_or_null("BotController") == null,
		"no BotController under Main while p2_is_cpu is false"
	)
	MatchConfig.reset()


## NORMAL would do too, but BRUTAL (difficulty 2) proves the tier is copied, not defaulted.
func test_cpu_mode_adds_a_bot_that_drives_player2(ctx: TestContext) -> void:
	MatchConfig.reset()
	MatchConfig.p2_is_cpu = true
	MatchConfig.difficulty = 2
	var main := _spawn_main(ctx)
	if main == null:
		MatchConfig.reset()
		return
	await ctx.step(1)
	var bot := main.get_node_or_null("BotController") as BotController
	ctx.check(bot != null, "Main has a BotController child in CPU mode")
	if bot == null:
		MatchConfig.reset()
		return
	ctx.check(bot.controlled_index == 2, "the bot controls Player 2")
	ctx.check(
		bot.difficulty == BotController.Difficulty.BRUTAL,
		"the bot's difficulty is MatchConfig.difficulty (2 = BRUTAL, got %d)" % bot.difficulty
	)
	ctx.check(bot.enabled, "the bot is enabled while the match runs")
	var p2 := main.get_node("Player2") as CharacterBody2D
	var start_x := p2.global_position.x
	await ctx.step(90)
	ctx.check(
		absf(p2.global_position.x - start_x) > 10.0,
		(
			"the bot has moved Player2 within 90 frames (x %.1f -> %.1f)"
			% [start_x, p2.global_position.x]
		)
	)
	_release_p2(ctx)
	MatchConfig.reset()


func test_match_end_sleeps_the_bot_and_down_returns_to_the_select(ctx: TestContext) -> void:
	MatchConfig.reset()
	MatchConfig.p2_is_cpu = true
	MatchConfig.stocks = 1
	var main := _spawn_main(ctx)
	if main == null:
		MatchConfig.reset()
		return
	var navigated: Array[String] = []
	main.connect("navigate", func(path: String) -> void: navigated.append(path))
	await ctx.step(1)
	var match_node: Match = main.get_node("Match")
	var bot := main.get_node_or_null("BotController") as BotController
	var p2 := main.get_node("Player2") as CharacterBody2D
	p2.global_position = BELOW_STAGE
	var frames := 0
	while match_node.winner_index == 0 and frames < 10:
		await ctx.step(1)
		frames += 1
	ctx.check(match_node.winner_index == 1, "Player1 wins once Player2 drops its only stock")
	ctx.check(bot != null and not bot.enabled, "the bot is disabled when the match ends")
	await ctx.step(1)
	for action in P2_ACTIONS:
		ctx.check(not Input.is_action_pressed(action), "%s is up the frame after the win" % action)
	ctx.check(navigated.is_empty(), "nothing navigated on its own")
	ctx.press("p1_down")
	await ctx.step(1)
	ctx.release("p1_down")
	ctx.check(
		navigated.size() == 1 and navigated[0] == SELECT_PATH,
		(
			"p1_down on the win screen emits navigate with the CharacterSelect path (got %s)"
			% [navigated]
		)
	)
	ctx.check(match_node.winner_index == 1, "going back to the select is not a rematch")
	ctx.press("p1_attack")
	await ctx.step(1)
	ctx.release("p1_attack")
	ctx.check(match_node.winner_index == 0, "Player1's attack still rematches")
	ctx.check(bot != null and bot.enabled, "the rematch wakes the bot again")
	_release_p2(ctx)
	MatchConfig.reset()
