extends RefCounted
## scenes/Main.tscn and prefabs/Platform.tscn load and are wired as the contract says:
## two indexed players standing on the floor, one-way platforms, the Wyrm's Ossuary layers,
## a medallion HUD bound to percentage, and a fight camera that frames both players.

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
			platform.get_node_or_null("Visual") == null,
			"%s has no Visual ColorRect (StageArt draws the shards)" % platform_name
		)
	ctx.check(
		main.get_node_or_null("Floor/Visual") == null,
		"Floor has no Visual ColorRect (StageArt draws the spine)"
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


func test_ossuary_layers_are_present(ctx: TestContext) -> void:
	var main := _spawn_main(ctx)
	if main == null:
		return
	await ctx.step(1)
	var backdrop_layer := main.get_node_or_null("BackdropLayer") as CanvasLayer
	ctx.check(
		backdrop_layer != null and backdrop_layer.layer == -10,
		"BackdropLayer is a CanvasLayer at layer -10"
	)
	var backdrop := main.get_node_or_null("BackdropLayer/Backdrop") as Sprite2D
	ctx.check(
		backdrop != null and backdrop.texture != null and backdrop.scale == Vector2(1.12, 1.12),
		"Backdrop sprite carries the ossuary painting at scale 1.12"
	)
	ctx.check(main.get_node_or_null("StageArt") is Node2D, "StageArt Node2D draws the bone stage")
	ctx.check(main.get_node_or_null("Mist") is Node2D, "Mist Node2D drifts over the stage")
	var vfx := main.get_node_or_null("Vfx") as Node2D
	ctx.check(vfx != null and vfx.z_index == 5, "Vfx Node2D sits at z_index 5")
	var order := [
		main.get_node("StageArt").get_index(),
		main.get_node("Mist").get_index(),
		main.get_node("Player1").get_index(),
	]
	ctx.check(
		order[0] < order[1] and order[1] < order[2],
		"StageArt and Mist are drawn before the players (child order)"
	)
	var vignette_layer := main.get_node_or_null("VignetteLayer") as CanvasLayer
	ctx.check(vignette_layer != null and vignette_layer.layer == 5, "VignetteLayer is at layer 5")
	var vignette := main.get_node_or_null("VignetteLayer/Vignette") as TextureRect
	ctx.check(
		(
			vignette != null
			and vignette.texture is GradientTexture2D
			and vignette.size == Vector2(1280, 720)
		),
		"Vignette is a full-screen GradientTexture2D"
	)
	var hud := main.get_node_or_null("HUD") as CanvasLayer
	ctx.check(hud != null and hud.layer == 10, "HUD is a CanvasLayer at layer 10")


func test_hud_medallions_match_contract(ctx: TestContext) -> void:
	var main := _spawn_main(ctx)
	if main == null:
		return
	await ctx.step(1)
	var stage_name := main.get_node_or_null("HUD/Root/StageName") as Label
	ctx.check(
		stage_name != null and stage_name.text == "Wyrm's Ossuary", "StageName reads Wyrm's Ossuary"
	)
	var rows := [
		["P1", "Kage", BrawlTheme.P1_COLOR, "kage_portrait.png"],
		["P2", "Ignis", BrawlTheme.P2_COLOR, "ignis_portrait.png"],
	]
	for row: Array in rows:
		var base := "HUD/Root/%sMedallion/" % row[0]
		var name_label := main.get_node_or_null(base + "Name") as Label
		ctx.check(
			name_label != null and name_label.text == row[1],
			"%sMedallion/Name reads %s" % [row[0], row[1]]
		)
		ctx.check(
			name_label != null and name_label.get_theme_color("font_color").is_equal_approx(row[2]),
			"%sMedallion/Name uses the player colour" % row[0]
		)
		var portrait := main.get_node_or_null(base + "Portrait") as TextureRect
		ctx.check(
			(
				portrait != null
				and portrait.texture != null
				and portrait.texture.resource_path.ends_with(row[3])
			),
			"%sMedallion/Portrait shows %s" % [row[0], row[3]]
		)
		ctx.check(
			main.get_node_or_null(base + "Ring") is Control, "%sMedallion has a Ring" % row[0]
		)
		var percent := main.get_node_or_null(base + "%sLabel" % row[0]) as Label
		ctx.check(percent != null and percent.text == "0%", "%sLabel starts at 0%%" % row[0])
	ctx.check(main.get_node_or_null("HUD/Root/Controls") is Label, "HUD has a Controls label")


func test_hud_label_tracks_player_percentage(ctx: TestContext) -> void:
	var main := _spawn_main(ctx)
	if main == null:
		return
	await ctx.step(1)
	var p1_label := main.get_node_or_null("HUD/Root/P1Medallion/P1Label") as Label
	var p2_label := main.get_node_or_null("HUD/Root/P2Medallion/P2Label") as Label
	if p1_label == null or p2_label == null:
		ctx.check(false, "HUD/Root/P1Medallion/P1Label and P2Medallion/P2Label exist")
		return
	var p2 := main.get_node("Player2") as CharacterBody2D
	p2.call("take_damage", 260.0, Vector2(1, 0), 8.0)
	await ctx.step(1)
	ctx.check(
		p2_label.text.contains("8%"),
		"P2Label shows 8% after Player2.take_damage (unconnected percentage_changed breaks this)"
	)
	ctx.check(
		p1_label.text == "0%",
		"P1Label is untouched by a hit on Player2 (crossed wiring breaks this)"
	)


func test_percent_color_table(ctx: TestContext) -> void:
	var table := [
		[0.0, BrawlTheme.PERCENT_WHITE],
		[34.9, BrawlTheme.PERCENT_WHITE],
		[35.0, BrawlTheme.PERCENT_YELLOW],
		[74.9, BrawlTheme.PERCENT_YELLOW],
		[75.0, BrawlTheme.PERCENT_ORANGE],
		[119.9, BrawlTheme.PERCENT_ORANGE],
		[120.0, BrawlTheme.PERCENT_RED],
	]
	for row: Array in table:
		ctx.check(
			BrawlTheme.percent_color(row[0]) == row[1], "percent_color(%.1f) threshold" % row[0]
		)
	ctx.check(BrawlTheme.player_color(1) == BrawlTheme.P1_COLOR, "player_color(1) is cyan")
	ctx.check(BrawlTheme.player_color(2) == BrawlTheme.P2_COLOR, "player_color(2) is crimson")


## With Player2 moved to x 1100 the midpoint is 810 and the distance 580, so the camera must
## drift right of 700 and zoom out below its spawn value (700 / 540 clamps to max_zoom).
func test_fight_camera_frames_both_players(ctx: TestContext) -> void:
	var main := _spawn_main(ctx)
	if main == null:
		return
	var camera := main.get_node_or_null("Camera2D") as Camera2D
	ctx.check(camera != null and camera.enabled, "Camera2D exists and is enabled")
	if camera == null:
		return
	ctx.check(
		(
			camera.limit_left == -200
			and camera.limit_top == -240
			and camera.limit_right == 1480
			and camera.limit_bottom == 960
		),
		"Camera2D limits are (-200, -240)..(1480, 960)"
	)
	var min_zoom := float(camera.get("min_zoom"))
	var max_zoom := float(camera.get("max_zoom"))
	await ctx.step(90)
	var spawn_zoom := camera.zoom.x
	ctx.check(
		spawn_zoom >= min_zoom and spawn_zoom <= max_zoom,
		"camera zoom stays within [min_zoom, max_zoom] at spawn (actual %.3f)" % spawn_zoom
	)
	ctx.check_near(camera.position.x, 640.0, 5.0, "camera centres between the spawn points")
	var p2 := main.get_node("Player2") as CharacterBody2D
	p2.global_position = Vector2(1100, 540)
	await ctx.step(90)
	ctx.check(
		camera.position.x > 700.0,
		"camera follows the midpoint right (actual x %.1f)" % camera.position.x
	)
	ctx.check(
		camera.zoom.x < spawn_zoom,
		"camera zooms out as the fighters separate (%.3f < %.3f)" % [camera.zoom.x, spawn_zoom]
	)


func test_fight_camera_shake_decays_to_zero(ctx: TestContext) -> void:
	var camera := ctx.add(load("res://scripts/fight_camera.gd").new()) as Camera2D
	await ctx.step(1)
	camera.call("shake", 10.0, 4)
	await ctx.step(1)
	ctx.check(camera.offset != Vector2.ZERO, "camera offset is displaced while shaking")
	ctx.check(camera.offset.length() <= 10.0 * sqrt(2.0), "shake offset is bounded by intensity")
	await ctx.step(4)
	ctx.check(camera.offset == Vector2.ZERO, "camera offset returns to zero after the shake")
