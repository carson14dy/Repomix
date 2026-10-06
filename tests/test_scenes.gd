extends RefCounted
## scenes/Main.tscn and prefabs/Platform.tscn load and are wired as the contract says:
## two indexed players standing on the floor, one-way platforms, HUD labels bound to percentage.

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"


func _spawn_main(ctx: TestContext) -> Node2D:
	var scene: PackedScene = load(MAIN_SCENE_PATH)
	ctx.check(scene != null, "Main.tscn loads (a missing ext_resource or bad .tscn breaks this)")
	if scene == null:
		return null
	var main := scene.instantiate() as Node2D
	ctx.check(main != null, "Main.tscn root instantiates as Node2D")
	if main == null:
		return null
	ctx.add(main)
	return main


func test_main_has_two_indexed_players(ctx: TestContext) -> void:
	var main := _spawn_main(ctx)
	if main == null:
		return
	await ctx.step(1)
	var p1 := main.get_node_or_null("Player1") as CharacterBody2D
	var p2 := main.get_node_or_null("Player2") as CharacterBody2D
	ctx.check(p1 != null, "Main has a Player1 CharacterBody2D (renaming the node breaks this)")
	ctx.check(p2 != null, "Main has a Player2 CharacterBody2D (renaming the node breaks this)")
	if p1 == null or p2 == null:
		return
	ctx.check(int(p1.get("player_index")) == 1, "Player1 instance overrides player_index = 1")
	ctx.check(int(p2.get("player_index")) == 2, "Player2 instance overrides player_index = 2")
	ctx.check(int(p1.get("start_facing")) == 1, "Player1 starts facing right")
	ctx.check(int(p2.get("start_facing")) == -1, "Player2 starts facing left")
	ctx.check(
		p1.position.x < p2.position.x, "Player1 spawns left of Player2 (swapped spawns break this)"
	)


func test_both_players_stand_on_floor(ctx: TestContext) -> void:
	var main := _spawn_main(ctx)
	if main == null:
		return
	var p1 := main.get_node("Player1") as CharacterBody2D
	var p2 := main.get_node("Player2") as CharacterBody2D
	await ctx.step(120)
	ctx.check(
		p1.is_on_floor(), "Player1 is on the floor after 120 frames (floor misplaced or no gravity)"
	)
	ctx.check(
		p2.is_on_floor(), "Player2 is on the floor after 120 frames (floor misplaced or no gravity)"
	)
	ctx.check(
		p1.position.y < 620.0 and p2.position.y < 620.0,
		"players rest above the floor's center (falling through breaks this)"
	)


func test_platforms_are_one_way(ctx: TestContext) -> void:
	var main := _spawn_main(ctx)
	if main == null:
		return
	await ctx.step(1)
	for platform_name in ["PlatformLeft", "PlatformRight"]:
		var platform := main.get_node_or_null(platform_name) as StaticBody2D
		ctx.check(
			platform != null, "%s is a StaticBody2D instance of Platform.tscn" % platform_name
		)
		if platform == null:
			continue
		var shape := platform.get_node_or_null("CollisionShape2D") as CollisionShape2D
		ctx.check(
			shape != null and shape.one_way_collision,
			"%s CollisionShape2D has one_way_collision" % platform_name
		)
		ctx.check(platform.collision_layer == 1, "%s is on physics layer 1 (world)" % platform_name)
		ctx.check(
			platform.get_node_or_null("Visual") is ColorRect,
			"%s has a Visual ColorRect" % platform_name
		)


func test_platform_prefab_shape_matches_contract(ctx: TestContext) -> void:
	var scene: PackedScene = load("res://prefabs/Platform.tscn")
	ctx.check(scene != null, "Platform.tscn loads")
	if scene == null:
		return
	var platform := ctx.add(scene.instantiate()) as StaticBody2D
	await ctx.step(1)
	var shape := platform.get_node("CollisionShape2D") as CollisionShape2D
	var rect := shape.shape as RectangleShape2D
	ctx.check(
		rect != null and rect.size == Vector2(240, 20), "Platform shape is a 240x20 rectangle"
	)
	var visual := platform.get_node("Visual") as ColorRect
	ctx.check(
		visual.size == Vector2(240, 20) and visual.position == Vector2(-120, -10),
		"Platform Visual is 240x20 centred on the body (offset drift breaks this)"
	)


func test_hud_label_tracks_player_percentage(ctx: TestContext) -> void:
	var main := _spawn_main(ctx)
	if main == null:
		return
	await ctx.step(1)
	var p1_label := main.get_node_or_null("HUD/P1Label") as Label
	var p2_label := main.get_node_or_null("HUD/P2Label") as Label
	ctx.check(p1_label != null and p1_label.text == "P1  0%", "P1Label starts at 'P1  0%'")
	ctx.check(p2_label != null and p2_label.text == "P2  0%", "P2Label starts at 'P2  0%'")
	ctx.check(main.get_node_or_null("HUD/Controls") is Label, "HUD has a Controls label")
	var p2 := main.get_node("Player2") as CharacterBody2D
	p2.call("take_damage", 260.0, Vector2(1, 0), 8.0)
	await ctx.step(1)
	ctx.check(
		p2_label != null and p2_label.text.contains("8%"),
		"P2Label shows 8% after Player2.take_damage (unconnected percentage_changed breaks this)"
	)
	ctx.check(
		p1_label != null and p1_label.text == "P1  0%",
		"P1Label is untouched by a hit on Player2 (crossed label wiring breaks this)"
	)
