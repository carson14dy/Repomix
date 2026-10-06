extends RefCounted
## Player movement physics: gravity, friction, acceleration, fast-fall, jump buffering, facing.
## Expected values are hand-derived from the player.gd tunables at dt = 1/60.

const FAR_ABOVE := Vector2(600, -2000)
const FLOOR_Y := 3000.0
## Floor center for grounded tests; default make_floor size is 1200x40 so its top is y - 20.
const GROUND_CENTER := Vector2(600, 600)
const GROUND_TOP := 580.0
const PLAYER_HALF_HEIGHT := 28.0
const MAX_DROP_FRAMES := 200


func _airborne_player(ctx: TestContext, index: int = 1) -> CharacterBody2D:
	ctx.make_floor(Vector2(600, FLOOR_Y))
	return ctx.spawn_player(index, FAR_ABOVE)


## Spawn a player standing on a floor and wait until is_on_floor() reports it.
func _grounded_player(ctx: TestContext, index: int = 1, x: float = 600.0) -> CharacterBody2D:
	var player := ctx.spawn_player(index, Vector2(x, GROUND_TOP - PLAYER_HALF_HEIGHT))
	await ctx.step(3)
	ctx.check(player.is_on_floor(), "player %d settles onto the floor" % index)
	return player


## Drop a fresh player from DROP_POS with no input; returns the number of frames stepped
## until is_on_floor() became true. `press_at_frame` (0 = never) taps p1_jump for one frame.
func _drop_until_landing(ctx: TestContext, press_at_frame: int) -> Dictionary:
	var player := ctx.spawn_player(1, Vector2(600, 400))
	for frame in range(1, MAX_DROP_FRAMES + 1):
		if frame == press_at_frame:
			ctx.press("p1_jump")
		await ctx.step(1)
		if frame == press_at_frame:
			ctx.release("p1_jump")
		if player.is_on_floor():
			return {"player": player, "frames": frame}
	return {"player": player, "frames": -1}


func test_gravity_accelerates_fall(ctx: TestContext) -> void:
	var player := _airborne_player(ctx)
	await ctx.step(30)
	ctx.check_near(player.velocity.y, 750.0, 10.0, "gravity 1500 px/s^2 over 30 frames")


func test_fall_speed_is_capped(ctx: TestContext) -> void:
	var player := _airborne_player(ctx)
	await ctx.step(90)
	ctx.check_near(player.velocity.y, 900.0, 10.0, "max_fall_speed caps velocity.y at 900")


func test_fast_fall_multiplies_gravity(ctx: TestContext) -> void:
	var player := _airborne_player(ctx)
	await ctx.step(10)
	ctx.check_near(player.velocity.y, 250.0, 10.0, "plain fall reaches 250 after 10 frames")
	ctx.press("p1_down")
	await ctx.step(10)
	ctx.check_near(player.velocity.y, 875.0, 15.0, "holding down applies 2.5x gravity (875)")


func test_fast_fall_control_without_down(ctx: TestContext) -> void:
	var player := _airborne_player(ctx)
	await ctx.step(20)
	ctx.check_near(player.velocity.y, 500.0, 15.0, "without down gravity stays 1x (500)")


func test_down_while_rising_does_not_fast_fall(ctx: TestContext) -> void:
	ctx.make_floor(GROUND_CENTER)
	var player := await _grounded_player(ctx)
	ctx.press("p1_jump")
	await ctx.step(1)
	ctx.release("p1_jump")
	ctx.check_near(player.velocity.y, -620.0, 1.0, "grounded jump sets jump_velocity -620")
	ctx.press("p1_down")
	await ctx.step(10)
	ctx.check_near(
		player.velocity.y, -370.0, 20.0, "down while rising keeps 1x gravity (-620 + 250)"
	)


func test_fast_fall_engages_after_apex(ctx: TestContext) -> void:
	ctx.make_floor(GROUND_CENTER)
	var player := await _grounded_player(ctx)
	ctx.press("p1_jump")
	await ctx.step(1)
	ctx.release("p1_jump")
	ctx.press("p1_down")
	var frames := 0
	while player.velocity.y < 0.0 and frames < 40:
		await ctx.step(1)
		frames += 1
	ctx.check(frames < 40, "jump reaches its apex within 40 frames while holding down")
	var apex_velocity := player.velocity.y
	await ctx.step(10)
	ctx.check_near(
		player.velocity.y,
		apex_velocity + 625.0,
		20.0,
		"after the apex, holding down applies 2.5x gravity (+625 over 10 frames)"
	)


func test_rising_without_down(ctx: TestContext) -> void:
	ctx.make_floor(GROUND_CENTER)
	var player := await _grounded_player(ctx)
	ctx.press("p1_jump")
	await ctx.step(1)
	ctx.release("p1_jump")
	await ctx.step(10)
	ctx.check_near(
		player.velocity.y, -370.0, 20.0, "rising without down adds 1x gravity (-620 + 250)"
	)


func test_air_friction_is_slight(ctx: TestContext) -> void:
	var player := _airborne_player(ctx)
	player.velocity.x = 300.0
	await ctx.step(30)
	ctx.check_near(player.velocity.x, 140.0, 8.0, "air_friction 320 px/s^2 over 0.5 s (300 - 160)")


func test_ground_friction_stops_quickly(ctx: TestContext) -> void:
	ctx.make_floor(GROUND_CENTER)
	var player := await _grounded_player(ctx)
	player.velocity.x = 300.0
	await ctx.step(10)
	ctx.check_near(
		player.velocity.x, 0.0, 1.0, "ground_friction 2400 px/s^2 stops 300 within 10 frames"
	)


func test_air_acceleration_is_slower(ctx: TestContext) -> void:
	var player := _airborne_player(ctx)
	ctx.press("p1_right")
	await ctx.step(10)
	ctx.check_near(player.velocity.x, 216.7, 8.0, "air_acceleration 1300 px/s^2 over 10 frames")


func test_ground_acceleration_reaches_run_speed(ctx: TestContext) -> void:
	ctx.make_floor(GROUND_CENTER)
	var player := await _grounded_player(ctx)
	ctx.press("p1_right")
	await ctx.step(10)
	ctx.check_near(
		player.velocity.x, 340.0, 1.0, "ground_acceleration caps at run_speed 340 in 10 frames"
	)


func test_grounded_jump_is_immediate(ctx: TestContext) -> void:
	ctx.make_floor(GROUND_CENTER)
	var player := await _grounded_player(ctx)
	ctx.press("p1_jump")
	await ctx.step(1)
	ctx.check(player.velocity.y <= -600.0, "grounded jump press jumps on the next frame")


func test_jump_buffer_accepts_early_press(ctx: TestContext) -> void:
	ctx.make_floor(GROUND_CENTER)
	var calibration := await _drop_until_landing(ctx, 0)
	var landing_frame: int = calibration["frames"]
	ctx.check(landing_frame > 10, "calibration drop lands after more than 10 frames")
	var buffered := await _drop_until_landing(ctx, landing_frame - 4)
	var player: CharacterBody2D = buffered["player"]
	var fastest_rise := 0.0
	for _frame in range(2):
		await ctx.step(1)
		fastest_rise = minf(fastest_rise, player.velocity.y)
	ctx.check(fastest_rise <= -600.0, "jump pressed 4 frames before landing fires within 2 frames")


func test_jump_buffer_expires(ctx: TestContext) -> void:
	ctx.make_floor(GROUND_CENTER)
	var calibration := await _drop_until_landing(ctx, 0)
	var landing_frame: int = calibration["frames"]
	var stale := await _drop_until_landing(ctx, landing_frame - 20)
	var player: CharacterBody2D = stale["player"]
	await ctx.step(3)
	ctx.check(player.velocity.y >= -1.0, "jump pressed 20 frames before landing is forgotten")


func test_facing_follows_input(ctx: TestContext) -> void:
	ctx.make_floor(GROUND_CENTER)
	var player := await _grounded_player(ctx)
	var sprite: Sprite2D = player.get_node("Sprite2D")
	var hitbox: Area2D = player.get_node("Hitbox")
	ctx.check(player.get("facing") == 1 and not sprite.flip_h, "default start_facing is right")
	ctx.check_near(hitbox.position.x, 26.0, 0.01, "hitbox sits at +26 when facing right")
	ctx.press("p1_left")
	await ctx.step(1)
	ctx.release("p1_left")
	ctx.check(player.get("facing") == -1, "holding left turns facing to -1")
	ctx.check(sprite.flip_h, "sprite flips horizontally when facing left")
	ctx.check_near(hitbox.position.x, -26.0, 0.01, "hitbox mirrors to -26 when facing left")
	await ctx.step(1)
	ctx.check(player.get("facing") == -1, "facing is kept when no horizontal input")


func test_players_read_only_their_own_actions(ctx: TestContext) -> void:
	ctx.make_floor(GROUND_CENTER)
	var player1 := await _grounded_player(ctx, 1, 300.0)
	var player2 := await _grounded_player(ctx, 2, 900.0)
	ctx.press("p2_right")
	await ctx.step(10)
	ctx.release("p2_right")
	ctx.check(player1.velocity.x == 0.0, "p2_right leaves player 1 still")
	ctx.check(player2.velocity.x > 200.0, "p2_right moves player 2")
	await ctx.step(10)
	ctx.press("p1_right")
	await ctx.step(10)
	ctx.check(player2.velocity.x == 0.0, "p1_right leaves player 2 still")
	ctx.check(player1.velocity.x > 200.0, "p1_right moves player 1")
