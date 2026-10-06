extends RefCounted
## Vfx lifetimes, the BrawlTheme damage colour rule, hud.gd against the medallion node
## contract, and the Main.tscn wiring that feeds both from a landed hit.

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const HUD_SCRIPT_PATH := "res://scripts/hud.gd"
const RING_SCRIPT_PATH := "res://scripts/medallion_ring.gd"


func test_hit_spark_lives_nine_frames(ctx: TestContext) -> void:
	var vfx := ctx.add(Vfx.new()) as Vfx
	ctx.check(vfx.active_effect_count() == 0, "a fresh Vfx has no effects")
	vfx.hit_spark(Vector2(100, 100), BrawlTheme.P1_COLOR, false)
	ctx.check(vfx.active_effect_count() == 1, "hit_spark adds one effect")
	await ctx.step(8)
	ctx.check(vfx.active_effect_count() == 1, "the spark is still alive after 8 frames")
	await ctx.step(1)
	ctx.check(vfx.active_effect_count() == 0, "the spark is gone after 9 frames")


func test_effect_lifetimes(ctx: TestContext) -> void:
	var vfx := ctx.add(Vfx.new()) as Vfx
	vfx.hit_spark(Vector2.ZERO, BrawlTheme.P2_COLOR, true)
	vfx.slash_arc(Vector2.ZERO, -1, BrawlTheme.P1_COLOR)
	vfx.dust(Vector2.ZERO)
	ctx.check(vfx.active_effect_count() == 3, "three effects queued at once")
	await ctx.step(9)
	ctx.check(vfx.active_effect_count() == 2, "slash_arc (9 frames) expires first")
	await ctx.step(3)
	ctx.check(vfx.active_effect_count() == 1, "dust (12 frames) expires next")
	await ctx.step(2)
	ctx.check(vfx.active_effect_count() == 0, "a strong spark (14 frames) expires last")


func test_percent_color_table(ctx: TestContext) -> void:
	var table := [
		[0.0, BrawlTheme.PERCENT_WHITE, "0 -> white"],
		[34.9, BrawlTheme.PERCENT_WHITE, "34.9 -> white"],
		[35.0, BrawlTheme.PERCENT_YELLOW, "35 -> yellow"],
		[74.9, BrawlTheme.PERCENT_YELLOW, "74.9 -> yellow"],
		[75.0, BrawlTheme.PERCENT_ORANGE, "75 -> orange"],
		[119.9, BrawlTheme.PERCENT_ORANGE, "119.9 -> orange"],
		[120.0, BrawlTheme.PERCENT_RED, "120 -> red"],
	]
	for row: Array in table:
		ctx.check(BrawlTheme.percent_color(row[0]) == row[1], "percent_color %s" % row[2])
	await ctx.step(1)


## A hand-built Main-shaped tree: Player1/Player2 beside a HUD CanvasLayer whose Root runs
## hud.gd over the P%dMedallion / P%dLabel / Ring node contract.
func _build_hud(ctx: TestContext, with_medallions: bool) -> Dictionary:
	var main := ctx.add(Node2D.new())
	var nodes := {"main": main}
	for index: int in [1, 2]:
		var player: CharacterBody2D = load(TestContext.PLAYER_SCENE_PATH).instantiate()
		player.name = "Player%d" % index
		player.set("player_index", index)
		player.position = Vector2(400 * index, 100)
		main.add_child(player)
		nodes["player%d" % index] = player
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	main.add_child(layer)
	var root := Control.new()
	root.name = "Root"
	root.set_script(load(HUD_SCRIPT_PATH))
	if with_medallions:
		for index: int in [1, 2]:
			var medallion := Control.new()
			medallion.name = "P%dMedallion" % index
			var label := Label.new()
			label.name = "P%dLabel" % index
			label.text = "0%"
			medallion.add_child(label)
			var ring := Control.new()
			ring.name = "Ring"
			ring.set_script(load(RING_SCRIPT_PATH))
			medallion.add_child(ring)
			root.add_child(medallion)
			nodes["label%d" % index] = label
			nodes["ring%d" % index] = ring
	layer.add_child(root)
	return nodes


func test_hud_labels_and_rings_follow_percentage(ctx: TestContext) -> void:
	var hud := _build_hud(ctx, true)
	await ctx.step(1)
	var p2_label: Label = hud["label2"]
	var p1_label: Label = hud["label1"]
	hud["player2"].call("take_damage", 260.0, Vector2(1, 0), 8.0)
	ctx.check(
		p2_label.text == "8%", "P2Label reads '8%%' after 8 damage (got '%s')" % p2_label.text
	)
	ctx.check(
		p2_label.get_theme_color("font_color") == BrawlTheme.PERCENT_WHITE,
		"P2Label is PERCENT_WHITE below 35"
	)
	ctx.check(
		hud["ring2"].get("ring_color") == BrawlTheme.PERCENT_WHITE,
		"P2 ring follows percent_color (white at 8)"
	)
	ctx.check(p1_label.text == "0%", "P1Label is untouched by a hit on Player2")
	hud["player1"].call("take_damage", 0.0, Vector2(1, 0), 40.0)
	hud["player1"].call("take_damage", 0.0, Vector2(1, 0), 40.0)
	ctx.check(p1_label.text == "80%", "P1Label accumulates to '80%%' (got '%s')" % p1_label.text)
	ctx.check(
		p1_label.get_theme_color("font_color") == BrawlTheme.PERCENT_ORANGE,
		"P1Label turns PERCENT_ORANGE at 80"
	)
	ctx.check(
		hud["ring1"].get("ring_color") == BrawlTheme.PERCENT_ORANGE, "P1 ring turns orange at 80"
	)


func test_hud_without_medallions_reports_and_survives(ctx: TestContext) -> void:
	var hud := _build_hud(ctx, false)
	await ctx.step(1)
	hud["player2"].call("take_damage", 260.0, Vector2(1, 0), 8.0)
	await ctx.step(1)
	ctx.check(
		is_instance_valid(hud["main"]) and hud["player2"].get("percentage") == 8.0,
		"a HUD with no medallion nodes push_errors (see log) instead of crashing the fight"
	)


func test_main_hit_feeds_vfx_and_hud(ctx: TestContext) -> void:
	var scene: PackedScene = load(MAIN_SCENE_PATH)
	ctx.check(scene != null, "Main.tscn loads")
	if scene == null:
		return
	var main := ctx.add(scene.instantiate()) as Node2D
	var vfx := main.get_node_or_null("Vfx") as Vfx
	var p2_label := main.get_node_or_null("HUD/Root/P2Medallion/P2Label") as Label
	ctx.check(vfx != null, "Main has a Vfx node running vfx.gd")
	ctx.check(p2_label != null, "Main has HUD/Root/P2Medallion/P2Label")
	if vfx == null or p2_label == null:
		return
	var p1 := main.get_node("Player1") as CharacterBody2D
	var p2 := main.get_node("Player2") as CharacterBody2D
	# Spawn y 540 -> standing y 568 is a 28 px drop: 0.5 * 1500 * t^2 = 28 takes ~12 frames.
	await ctx.step(20)
	ctx.check(p1.is_on_floor() and p2.is_on_floor(), "both fighters settle on the spine")
	# Bring Player2 within Player1's hitbox reach (hitbox at +26, 40 wide) before swinging.
	p2.global_position = p1.global_position + Vector2(40, 0)
	await ctx.step(2)
	var hits: Array = []
	p1.connect("hit_landed", func(a: int, v: int) -> void: hits.append([a, v]))
	ctx.press("p1_attack")
	await ctx.step(1)
	ctx.release("p1_attack")
	var frames := 0
	while hits.is_empty() and frames < 8:
		await ctx.step(1)
		frames += 1
	ctx.check(hits == [[1, 2]], "Player1's swing lands on Player2 (got %s)" % [hits])
	await ctx.step(1)
	ctx.check(vfx.active_effect_count() > 0, "Vfx has live effects within 2 frames of the hit")
	ctx.check(
		p2_label.text.contains("8%"),
		"HUD/Root/P2Medallion/P2Label shows 8%% after the hit (got '%s')" % p2_label.text
	)
