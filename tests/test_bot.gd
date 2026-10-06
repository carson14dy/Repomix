extends RefCounted
## BotController (prefabs/BotController.tscn) drives Player 2 through the p2_* InputMap
## actions: approach and hit, recover from off stage, let go when hit, press nothing when
## disabled. BRUTAL with seed 11 so every chance is 1.0 (0.9 for the platform jump).

const BOT_SCENE_PATH := "res://prefabs/BotController.tscn"
## Arena floor: top at y 580 spanning x 190..1090, as in scenes/Main.tscn.
const FLOOR_CENTER := Vector2(640, 600)
const FLOOR_SIZE := Vector2(900, 40)
const P1_SPAWN := Vector2(520, 540)
const P2_SPAWN := Vector2(760, 540)
const P2_ACTIONS: Array[String] = ["p2_left", "p2_right", "p2_jump", "p2_down", "p2_attack"]


func _spawn_bot(ctx: TestContext, me: Node2D, opponent: Node2D, enabled: bool = true) -> Node:
	var scene: PackedScene = load(BOT_SCENE_PATH)
	var bot := scene.instantiate()
	bot.set("controlled_index", 2)
	bot.set("difficulty", BotController.Difficulty.BRUTAL)
	bot.set("seed", 11)
	bot.set("enabled", enabled)
	bot.call("set_fighters", me, opponent)
	ctx.add(bot)
	return bot


func _any_p2_pressed() -> bool:
	for action in P2_ACTIONS:
		if Input.is_action_pressed(action):
			return true
	return false


## The bot releases its own actions in _exit_tree; this keeps the next suite clean even if
## a test fails half way.
func _release_p2(ctx: TestContext) -> void:
	for action in P2_ACTIONS:
		ctx.release(action)


# a. Approach: 240 px apart, the bot runs left (x < 700 after 60 frames: 60 frames of running
#    would cover ~300 px, so a bot that never moves or moves right fails) and then hits P1.
#    P1 is read as soon as it is hit because a later knock-off would respawn it at 0%.
func test_brutal_bot_approaches_and_hits(ctx: TestContext) -> void:
	ctx.make_floor(FLOOR_CENTER, FLOOR_SIZE)
	var p1 := ctx.spawn_player(1, P1_SPAWN)
	var p2 := ctx.spawn_player(2, P2_SPAWN)
	_spawn_bot(ctx, p2, p1)
	await ctx.step(60)
	ctx.check(
		p2.global_position.x < 700.0,
		"bot runs P2 toward P1 within 60 frames (x = %.1f)" % p2.global_position.x
	)
	var frames := 60
	while float(p1.get("percentage")) <= 0.0 and frames < 180:
		await ctx.step(1)
		frames += 1
	ctx.check(
		float(p1.get("percentage")) > 0.0,
		"bot lands a hit on P1 within 180 frames (hit at frame %d)" % frames
	)
	_release_p2(ctx)


# a2. In range but facing away (P2 spawns 40 px right of P1 with its default facing, right):
#     the hitbox only reaches forward, so the bot must turn before it can land anything.
func test_bot_turns_to_face_an_opponent_behind_it(ctx: TestContext) -> void:
	ctx.make_floor(FLOOR_CENTER, FLOOR_SIZE)
	var p1 := ctx.spawn_player(1, P1_SPAWN)
	var p2 := ctx.spawn_player(2, P1_SPAWN + Vector2(40, 0))
	_spawn_bot(ctx, p2, p1)
	var frames := 0
	while float(p1.get("percentage")) <= 0.0 and frames < 60:
		await ctx.step(1)
		frames += 1
	ctx.check(int(p2.get("facing")) == -1, "P2 turned to face P1 on its left")
	ctx.check(
		float(p1.get("percentage")) > 0.0,
		"bot hits an opponent that started behind it within 60 frames (hit at frame %d)" % frames
	)
	ctx.check(
		absf(p2.global_position.x - (P1_SPAWN.x + 40.0)) < 8.0,
		"turning was a tap, not a run (P2 x = %.1f)" % p2.global_position.x
	)
	_release_p2(ctx)


# b. Recovery: launched off the right edge and airborne, the bot holds left until it is back
#    over the floor and lands on it. From x 1200 only holding left gets back under 1090.
func test_bot_recovers_from_off_stage(ctx: TestContext) -> void:
	ctx.make_floor(FLOOR_CENTER, FLOOR_SIZE)
	var p1 := ctx.spawn_player(1, P1_SPAWN)
	var p2 := ctx.spawn_player(2, Vector2(1200, 300))
	_spawn_bot(ctx, p2, p1)
	await ctx.step(6)
	ctx.check(Input.is_action_pressed("p2_left"), "off stage right, the bot holds p2_left")
	ctx.check(not Input.is_action_pressed("p2_down"), "no fast-fall while off stage")
	var frames := 6
	var recovered := false
	while frames < 240:
		await ctx.step(1)
		frames += 1
		if p2.global_position.x < 1090.0 and p2.is_on_floor():
			recovered = true
			break
	ctx.check(
		recovered,
		(
			"P2 is back over the floor and standing on it within 240 frames (x = %.1f, y = %.1f)"
			% [p2.global_position.x, p2.global_position.y]
		)
	)
	ctx.check(p2.global_position.y < 600.0, "P2 did not fall past the floor")
	_release_p2(ctx)


# c. Being hit releases everything on the very next frame, whatever the bot was holding.
func test_bot_releases_everything_in_knockback(ctx: TestContext) -> void:
	ctx.make_floor(FLOOR_CENTER, FLOOR_SIZE)
	var p1 := ctx.spawn_player(1, P1_SPAWN)
	var p2 := ctx.spawn_player(2, P2_SPAWN)
	_spawn_bot(ctx, p2, p1)
	await ctx.step(12)
	ctx.check(Input.is_action_pressed("p2_left"), "bot is holding p2_left while approaching")
	p2.take_damage(300.0, Vector2(1, -1).normalized(), 10.0)
	await ctx.step(1)
	for action in P2_ACTIONS:
		ctx.check(not Input.is_action_pressed(action), "%s is released during knockback" % action)
	_release_p2(ctx)


# d. A disabled bot never presses anything, even standing 240 px from its target.
func test_disabled_bot_presses_nothing(ctx: TestContext) -> void:
	ctx.make_floor(FLOOR_CENTER, FLOOR_SIZE)
	var p1 := ctx.spawn_player(1, P1_SPAWN)
	var p2 := ctx.spawn_player(2, P2_SPAWN)
	_spawn_bot(ctx, p2, p1, false)
	var pressed_once := false
	for _frame in range(30):
		await ctx.step(1)
		pressed_once = pressed_once or _any_p2_pressed()
	ctx.check(not pressed_once, "disabled bot presses no p2_* action over 30 frames")
	ctx.check_near(p2.global_position.x, P2_SPAWN.x, 0.01, "P2 has not moved horizontally")
	_release_p2(ctx)


# e. Disabling a running bot lets go of what it was holding.
func test_disabling_releases_held_actions(ctx: TestContext) -> void:
	ctx.make_floor(FLOOR_CENTER, FLOOR_SIZE)
	var p1 := ctx.spawn_player(1, P1_SPAWN)
	var p2 := ctx.spawn_player(2, P2_SPAWN)
	var bot := _spawn_bot(ctx, p2, p1)
	await ctx.step(12)
	ctx.check(Input.is_action_pressed("p2_left"), "bot is holding p2_left before being disabled")
	bot.set("enabled", false)
	ctx.check(not _any_p2_pressed(), "setting enabled = false releases every p2_* action")
	await ctx.step(5)
	ctx.check(not _any_p2_pressed(), "a disabled bot stays quiet on later frames")
	_release_p2(ctx)


# f. A KO'd fighter (Player.active false until respawn) has nobody to steer, and a KO'd
#    opponent nobody to chase: the bot lets go and idles until both are back, then resumes.
func test_bot_idles_while_either_fighter_is_knocked_out(ctx: TestContext) -> void:
	ctx.make_floor(FLOOR_CENTER, FLOOR_SIZE)
	var p1 := ctx.spawn_player(1, P1_SPAWN)
	var p2 := ctx.spawn_player(2, P2_SPAWN)
	_spawn_bot(ctx, p2, p1)
	await ctx.step(12)
	ctx.check(Input.is_action_pressed("p2_left"), "bot is holding p2_left while approaching")
	p2.call("ko")
	await ctx.step(1)
	ctx.check(
		not _any_p2_pressed(), "the bot releases everything the frame after its fighter is KO'd"
	)
	await ctx.step(6)
	ctx.check(not _any_p2_pressed(), "and presses nothing while the fighter is inactive")
	p2.call("respawn")
	p1.call("ko")
	await ctx.step(6)
	ctx.check(not _any_p2_pressed(), "a KO'd opponent keeps the bot idle too")
	p1.call("respawn")
	await ctx.step(6)
	ctx.check(Input.is_action_pressed("p2_left"), "the bot resumes the chase once both are active")
	_release_p2(ctx)
