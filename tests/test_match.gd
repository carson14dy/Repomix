extends RefCounted
## Round flow in scenes/Main.tscn (Match, scripts/match.gd): leaving the blast zone costs a
## stock and hides the fighter until it respawns at its spawn point respawn_delay_frames later
## at 0%; the third KO ends the match, shows the win screen, and an attack press rematches.
## Expected frame counts come from the Match defaults: 3 stocks, 60-frame respawn delay,
## blast zone (-260, -420)..(1540, 1100).

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const RESPAWN_FRAMES := 60
const BELOW_STAGE := Vector2(640, 1150)
const P2_SPAWN := Vector2(760, 540)


## Main with both fighters settled on the spine (the spawn is a 28 px drop, about 12 frames).
func _spawn_main(ctx: TestContext) -> Node2D:
	var scene: PackedScene = load(MAIN_SCENE_PATH)
	ctx.check(scene != null, "Main.tscn loads")
	if scene == null:
		return null
	var main := ctx.add(scene.instantiate()) as Node2D
	await ctx.step(20)
	return main


## Drop `player` below the stage and step one frame: the Match KOs it on that frame.
func _ko(ctx: TestContext, player: CharacterBody2D) -> void:
	player.global_position = BELOW_STAGE
	await ctx.step(1)


func test_main_has_match_sfx_and_hidden_win_layer(ctx: TestContext) -> void:
	var main := await _spawn_main(ctx)
	if main == null:
		return
	var match_node := main.get_node_or_null("Match")
	ctx.check(match_node is Match, "Main has a Match node running match.gd")
	if match_node == null:
		return
	ctx.check(int(match_node.get("stocks_per_player")) == 3, "Match starts with 3 stocks each")
	ctx.check(
		int(match_node.get("respawn_delay_frames")) == RESPAWN_FRAMES, "Match respawns after 60"
	)
	ctx.check(
		match_node.get("blast_zone") == Rect2(-260, -420, 1800, 1520),
		"blast zone is (-260, -420)..(1540, 1100)"
	)
	ctx.check(main.get_node_or_null("Sfx") is Sfx, "Main has an Sfx node (prefabs/Sfx.tscn)")
	var win_layer := main.get_node_or_null("WinLayer") as CanvasLayer
	ctx.check(
		win_layer != null and win_layer.layer == 20 and not win_layer.visible,
		"WinLayer is a hidden CanvasLayer at layer 20 while the match runs"
	)
	for index: int in [1, 2]:
		var pips := main.get_node_or_null("HUD/Root/P%dMedallion/Stocks" % index)
		ctx.check(
			pips != null and int(pips.get("stocks")) == 3,
			"HUD/Root/P%dMedallion/Stocks shows 3 stocks at the start" % index
		)


func test_leaving_the_bottom_costs_a_stock_and_respawns(ctx: TestContext) -> void:
	var main := await _spawn_main(ctx)
	if main == null:
		return
	var match_node: Match = main.get_node("Match")
	var p2 := main.get_node("Player2") as CharacterBody2D
	var pips := main.get_node("HUD/Root/P2Medallion/Stocks")
	var stock_events: Array = []
	match_node.stocks_changed.connect(
		func(index: int, stocks: int) -> void: stock_events.append([index, stocks])
	)
	p2.call("take_damage", 0.0, Vector2(1, 0), 40.0)
	await _ko(ctx, p2)
	ctx.check(not p2.visible, "a fighter below y 1100 is hidden on the frame it leaves the zone")
	ctx.check(not bool(p2.get("active")), "the KO'd fighter is inactive")
	ctx.check(stock_events == [[2, 2]], "stocks_changed(2, 2) fires once (got %s)" % [stock_events])
	ctx.check(int(pips.get("stocks")) == 2, "P2 stock pips drop to 2")
	ctx.check(main.get_node("HUD/Root/P1Medallion/Stocks").get("stocks") == 3, "P1 keeps 3")
	await ctx.step(RESPAWN_FRAMES - 1)
	ctx.check(not p2.visible, "the fighter is still hidden 59 frames after the KO")
	await ctx.step(1)
	ctx.check(p2.visible, "the fighter respawns 60 frames after the KO")
	ctx.check(bool(p2.get("active")), "the respawned fighter is active again")
	ctx.check(p2.global_position == P2_SPAWN, "it respawns at its spawn point (760, 540)")
	ctx.check_near(p2.get("percentage"), 0.0, 0.01, "respawn resets the 40% to 0")
	ctx.check(p2.velocity == Vector2.ZERO, "respawn zeroes the velocity")


func test_sides_and_top_are_blast_zones(ctx: TestContext) -> void:
	var main := await _spawn_main(ctx)
	if main == null:
		return
	var match_node: Match = main.get_node("Match")
	var p1 := main.get_node("Player1") as CharacterBody2D
	var p2 := main.get_node("Player2") as CharacterBody2D
	p1.global_position = Vector2(-300, 540)
	p2.global_position = Vector2(1600, 540)
	await ctx.step(1)
	ctx.check(not p1.visible, "x = -300 is past the left blast line (-260)")
	ctx.check(not p2.visible, "x = 1600 is past the right blast line (1540)")
	ctx.check(match_node.stocks[1] == 2 and match_node.stocks[2] == 2, "both fighters lose a stock")
	await ctx.step(RESPAWN_FRAMES)
	ctx.check(p1.visible and p2.visible, "both respawn after 60 frames")
	p1.global_position = Vector2(640, -500)
	await ctx.step(1)
	ctx.check(not p1.visible, "y = -500 is past the top blast line (-420)")
	ctx.check(match_node.stocks[1] == 1, "the top KO costs Player1 a second stock")
	p2.global_position = Vector2(640, 1050)
	await ctx.step(1)
	ctx.check(p2.visible, "y = 1050 is still inside the zone (bottom line 1100)")


func test_ko_hides_the_body_from_hitboxes(ctx: TestContext) -> void:
	var main := await _spawn_main(ctx)
	if main == null:
		return
	var p1 := main.get_node("Player1") as CharacterBody2D
	var p2 := main.get_node("Player2") as CharacterBody2D
	await _ko(ctx, p2)
	# The hidden body waits at its spawn; Player1 stands there and swings through it.
	p1.global_position = P2_SPAWN + Vector2(-40, 0)
	await ctx.step(2)
	ctx.press("p1_attack")
	await ctx.step(1)
	ctx.release("p1_attack")
	await ctx.step(8)
	ctx.check_near(p2.get("percentage"), 0.0, 0.01, "a swing through a KO'd fighter does not hit")


func test_third_ko_ends_the_match(ctx: TestContext) -> void:
	var main := await _spawn_main(ctx)
	if main == null:
		return
	var match_node: Match = main.get_node("Match")
	var p1 := main.get_node("Player1") as CharacterBody2D
	var p2 := main.get_node("Player2") as CharacterBody2D
	var winners: Array = []
	match_node.match_ended.connect(func(index: int) -> void: winners.append(index))
	for _ko_number in range(2):
		await _ko(ctx, p2)
		await ctx.step(RESPAWN_FRAMES)
	ctx.check(p2.visible and match_node.stocks[2] == 1, "Player2 is back with 1 stock left")
	ctx.check(winners.is_empty(), "the match is still running at 1 stock")
	await _ko(ctx, p2)
	ctx.check(winners == [1], "match_ended(1) fires on the third KO (got %s)" % [winners])
	ctx.check(match_node.winner_index == 1, "winner_index is 1")
	ctx.check(match_node.stocks[2] == 0, "Player2 is at 0 stocks")
	await ctx.step(RESPAWN_FRAMES + 5)
	ctx.check(not p2.visible, "the loser does not respawn after the match ends")
	ctx.check(p1.visible, "the winner stays on stage")
	var win_layer := main.get_node("WinLayer") as CanvasLayer
	ctx.check(win_layer.visible, "WinLayer is shown when the match ends")
	var winner_label := main.get_node_or_null("WinLayer/Winner") as Label
	ctx.check(
		winner_label != null and winner_label.text == "Kage wins",
		"WinLayer/Winner reads 'Kage wins' (got '%s')" % (winner_label.text if winner_label else "")
	)
	ctx.check(
		(
			winner_label != null
			and winner_label.get_theme_color("font_color").is_equal_approx(BrawlTheme.P1_COLOR)
		),
		"WinLayer/Winner wears the winner's colour"
	)


func test_attack_press_rematches_after_the_match(ctx: TestContext) -> void:
	var main := await _spawn_main(ctx)
	if main == null:
		return
	var match_node: Match = main.get_node("Match")
	var p1 := main.get_node("Player1") as CharacterBody2D
	var p2 := main.get_node("Player2") as CharacterBody2D
	var restarts: Array = []
	match_node.match_restarted.connect(func() -> void: restarts.append(true))
	p1.call("take_damage", 0.0, Vector2(1, 0), 30.0)
	for _ko_number in range(3):
		await _ko(ctx, p1)
		await ctx.step(RESPAWN_FRAMES)
	ctx.check(match_node.winner_index == 2, "Player2 wins after three Player1 KOs")
	ctx.press("p2_attack")
	await ctx.step(1)
	ctx.release("p2_attack")
	ctx.check(restarts.size() == 1, "match_restarted fires once on the attack press")
	ctx.check(match_node.winner_index == 0, "winner_index returns to 0")
	ctx.check(
		match_node.stocks[1] == 3 and match_node.stocks[2] == 3, "both fighters are back to 3"
	)
	ctx.check(p1.visible and p2.visible, "both fighters are on stage again")
	ctx.check(p1.global_position == Vector2(520, 540), "Player1 is back at its spawn")
	ctx.check_near(p1.get("percentage"), 0.0, 0.01, "Player1's damage is reset")
	ctx.check(not main.get_node("WinLayer").visible, "WinLayer hides on rematch")
	ctx.check(
		int(main.get_node("HUD/Root/P1Medallion/Stocks").get("stocks")) == 3,
		"P1 stock pips refill to 3"
	)
	await ctx.step(1)
	ctx.check(match_node.winner_index == 0, "the match keeps running after the rematch frame")


func test_ko_plays_a_sound_and_shakes_the_camera(ctx: TestContext) -> void:
	var main := await _spawn_main(ctx)
	if main == null:
		return
	var sfx := main.get_node("Sfx")
	var camera := main.get_node("Camera2D") as Camera2D
	var p2 := main.get_node("Player2") as CharacterBody2D
	await _ko(ctx, p2)
	await ctx.step(1)
	var voice_playing := false
	for child in sfx.get_children():
		if child is AudioStreamPlayer and child.playing:
			voice_playing = true
	ctx.check(voice_playing, "an Sfx voice is playing the frame after a KO")
	ctx.check(camera.offset != Vector2.ZERO, "the camera shakes after a KO")
