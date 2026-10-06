extends RefCounted
## take_damage() formula, knockback state, hitbox integration, signals and respawn.
## Expected values are hand-derived from the player.gd tunables (dt = 1/60).

const FLOOR_CENTER := Vector2(600, 600)
## Default make_floor size is 1200x40, so its top is 580; players are 56 px tall.
const STAND_Y := 552.0
const MAX_FALL_FRAMES := 200


## P1 at x = 500 facing right, P2 at x = 540 inside P1's hitbox reach; both grounded.
func _face_off(ctx: TestContext) -> Array[CharacterBody2D]:
	ctx.make_floor(FLOOR_CENTER)
	var attacker := ctx.spawn_player(1, Vector2(500, STAND_Y))
	var victim := ctx.spawn_player(2, Vector2(540, STAND_Y))
	await ctx.step(3)
	ctx.check(attacker.is_on_floor() and victim.is_on_floor(), "both fighters start grounded")
	return [attacker, victim]


## Like ctx.spawn_player, but facing left (start_facing is read in _ready, so set it first).
func _spawn_facing_left(ctx: TestContext, player_index: int, pos: Vector2) -> CharacterBody2D:
	var scene: PackedScene = load(TestContext.PLAYER_SCENE_PATH)
	var player := scene.instantiate() as CharacterBody2D
	player.set("player_index", player_index)
	player.set("start_facing", -1)
	player.position = pos
	ctx.add(player)
	return player


## Step one frame at a time until `player` falls past `below_y`; false if it never does.
func _fall_past(ctx: TestContext, player: CharacterBody2D, below_y: float) -> bool:
	for _frame in range(MAX_FALL_FRAMES):
		await ctx.step(1)
		if player.global_position.y > below_y:
			return true
	return false


func _check_velocity(
	ctx: TestContext, player: CharacterBody2D, want: Vector2, tol: float, label: String
) -> void:
	ctx.check_near(player.velocity.x, want.x, tol, label + " (x)")
	ctx.check_near(player.velocity.y, want.y, tol, label + " (y)")


# a. actual_knockback = base_knockback * (percentage / 10), percentage after the hit.
func test_take_damage_formula(ctx: TestContext) -> void:
	ctx.make_floor(FLOOR_CENTER)
	var player := ctx.spawn_player(1, Vector2(600, STAND_Y))
	await ctx.step(1)
	player.take_damage(300.0, Vector2(1, 0), 20.0)
	ctx.check_near(player.get("percentage"), 20.0, 0.01, "first hit adds 20 percent")
	_check_velocity(ctx, player, Vector2(600, 0), 0.01, "knockback = 300 * (20 / 10) along +x")
	player.take_damage(300.0, Vector2(0, -1), 10.0)
	ctx.check_near(player.get("percentage"), 30.0, 0.01, "percentage accumulates to 30")
	_check_velocity(ctx, player, Vector2(0, -900), 0.01, "knockback = 300 * (30 / 10) along -y")
	await ctx.step(1)


# b. direction is normalized; a zero direction launches straight up.
func test_take_damage_normalizes_direction(ctx: TestContext) -> void:
	var player := ctx.spawn_player(1, Vector2(600, STAND_Y))
	player.take_damage(100.0, Vector2(3, -4), 10.0)
	_check_velocity(ctx, player, Vector2(60, -80), 0.01, "(3, -4) normalizes to (0.6, -0.8)")
	var other := ctx.spawn_player(2, Vector2(700, STAND_Y))
	other.take_damage(100.0, Vector2.ZERO, 10.0)
	_check_velocity(ctx, other, Vector2(0, -100), 0.01, "zero direction falls back to Vector2.UP")
	await ctx.step(1)


# c. The user's two-argument call shape adds the default 10 percent.
func test_take_damage_default_damage_is_ten(ctx: TestContext) -> void:
	var player := ctx.spawn_player(1, Vector2(600, STAND_Y))
	player.take_damage(100.0, Vector2(1, 0))
	ctx.check_near(player.get("percentage"), 10.0, 0.01, "take_damage(base, dir) adds 10 percent")
	_check_velocity(ctx, player, Vector2(100, 0), 0.01, "knockback = 100 * (10 / 10)")
	await ctx.step(1)


# d. Knockback state: input ignored, no air friction, gravity only, lasts knockback_stun_frames.
#    Jump and attack stay held through the stun and past its end: a button held through the
#    stun must not fire as a press when control returns.
func test_knockback_state_blocks_control(ctx: TestContext) -> void:
	ctx.make_floor(FLOOR_CENTER)
	var player := ctx.spawn_player(1, Vector2(600, STAND_Y))
	var hitbox_shape: CollisionShape2D = player.get_node("Hitbox/CollisionShape2D")
	await ctx.step(3)
	ctx.check(player.is_on_floor(), "player starts grounded")
	player.take_damage(400.0, Vector2(1, -1).normalized(), 10.0)
	_check_velocity(ctx, player, Vector2(282.84, -282.84), 0.05, "400 * (10 / 10) along (1, -1)")
	ctx.check(player.get("state") == Player.State.KNOCKBACK, "take_damage enters KNOCKBACK")
	ctx.press("p1_left")
	ctx.press("p1_jump")
	ctx.press("p1_attack")
	await ctx.step(10)
	ctx.check_near(
		player.velocity.x, 282.84, 0.5, "held left is ignored and no air friction during stun"
	)
	# 10 frames of gravity: 10 * 1500 / 60 = 250; a jump would have set -620.
	ctx.check_near(player.velocity.y, -32.84, 1.0, "gravity only during stun (jump ignored)")
	ctx.check(hitbox_shape.disabled, "attack pressed during stun does not activate the hitbox")
	await ctx.step(9)
	ctx.check(player.get("state") == Player.State.KNOCKBACK, "still KNOCKBACK after 19 frames")
	await ctx.step(1)
	ctx.check(player.get("state") == Player.State.NORMAL, "NORMAL after knockback_stun_frames 20")
	# The fighter lands 2 frames after control returns; a stale press would buffer a jump
	# that fires on landing (-620 px/s) and start an attack whose hitbox turns on 2 frames in.
	await ctx.step(4)
	ctx.check(
		player.velocity.y > -100.0,
		"jump held through the stun does not fire on exit (actual %.2f)" % player.velocity.y
	)
	ctx.check(hitbox_shape.disabled, "attack held through the stun does not start an attack")
	ctx.release("p1_jump")
	ctx.release("p1_attack")
	await ctx.step(6)
	ctx.check(
		player.velocity.x < 182.0,
		"held left slows the fighter once control returns (actual %.2f)" % player.velocity.x
	)


# e. Being hit cancels an attack in progress on the same call, counter included: the hitbox
#    stays off through the stun and a fresh attack starts the moment control returns.
func test_take_damage_cancels_attack(ctx: TestContext) -> void:
	var fighters := await _face_off(ctx)
	var attacker := fighters[0]
	var hitbox: Area2D = attacker.get_node("Hitbox")
	var hitbox_shape: CollisionShape2D = attacker.get_node("Hitbox/CollisionShape2D")
	ctx.press("p1_attack")
	await ctx.step(4)
	ctx.release("p1_attack")
	ctx.check(hitbox.get("active") and not hitbox_shape.disabled, "hitbox is active 4 frames in")
	attacker.take_damage(100.0, Vector2(-1, 0), 10.0)
	ctx.check(hitbox.get("active") == false, "hit cancels the attack: hitbox inactive")
	ctx.check(hitbox_shape.disabled, "hit cancels the attack: hitbox shape disabled")
	var stayed_disabled := true
	for _frame in range(20):
		await ctx.step(1)
		stayed_disabled = stayed_disabled and hitbox_shape.disabled
	ctx.check(stayed_disabled, "hitbox stays off for the whole stun with no input")
	ctx.check(attacker.get("state") == Player.State.NORMAL, "stun is over after 20 frames")
	# A fresh attack: startup 3 -> the shape is enabled at the start of the 4th frame. A stale
	# counter (15 frames of the cancelled swing left) would eat this press.
	ctx.press("p1_attack")
	await ctx.step(3)
	ctx.release("p1_attack")
	ctx.check(
		not hitbox_shape.disabled,
		"a new attack right after the stun turns the hitbox on in 3 frames"
	)


# f. Hitbox integration: attack_damage 8, knockback 260 * 0.8 along normalize(1, -0.75).
func test_attack_hits_once_with_knockback(ctx: TestContext) -> void:
	var fighters := await _face_off(ctx)
	var attacker := fighters[0]
	var victim := fighters[1]
	var hitbox_shape: CollisionShape2D = attacker.get_node("Hitbox/CollisionShape2D")
	var landed: Array = []
	var launch: Array[Vector2] = []
	attacker.connect(
		"hit_landed",
		func(a: int, v: int) -> void:
			landed.append([a, v])
			launch.append(victim.velocity)
	)
	ctx.check(hitbox_shape.disabled, "hitbox shape is disabled before attacking")
	ctx.press("p1_attack")
	await ctx.step(1)
	ctx.release("p1_attack")
	await ctx.step(8)
	ctx.check_near(
		victim.get("percentage"), 8.0, 0.01, "attack_damage 8 lands within startup+active frames"
	)
	ctx.check(victim.get("state") == Player.State.KNOCKBACK, "victim is in KNOCKBACK")
	# 260 * (8 / 10) = 208 along normalize(1, -0.75) = (0.8, -0.6), read when hit_landed fired.
	var hit_velocity := launch[0] if launch.size() == 1 else Vector2.ZERO
	ctx.check_near(hit_velocity.x, 166.4, 0.01, "launch x = 0.8 * 260 * 0.8 away from the attacker")
	ctx.check_near(hit_velocity.y, -124.8, 0.01, "launch y = -0.6 * 260 * 0.8 (upward)")
	ctx.check_near(
		victim.velocity.x, 166.4, 0.5, "x is still 166.4 after 9 frames: stun has no air friction"
	)
	ctx.check(
		victim.global_position.y < STAND_Y - 1.0, "victim has been lifted off the floor by the hit"
	)
	ctx.check(landed == [[1, 2]], "hit_landed emitted once with (attacker 1, victim 2)")
	ctx.check_near(attacker.get("percentage"), 0.0, 0.01, "attacker never hits itself")
	await ctx.step(11)
	ctx.check(hitbox_shape.disabled, "hitbox shape is disabled again 20 frames after the attack")
	await ctx.step(30)
	ctx.check_near(victim.get("percentage"), 8.0, 0.01, "one activation deals damage only once")


# g. percentage_changed(player_index, percentage).
func test_percentage_changed_signal(ctx: TestContext) -> void:
	var player := ctx.spawn_player(1, Vector2(600, STAND_Y))
	var received: Array = []
	player.connect(
		"percentage_changed", func(index: int, pct: float) -> void: received.append([index, pct])
	)
	player.take_damage(100.0, Vector2(1, 0), 8.0)
	ctx.check(received == [[1, 8.0]], "percentage_changed carries player_index and percentage")
	await ctx.step(1)


# h. Respawn resets position, percentage and state, and tells the HUD about the 0%.
func test_player_without_floor_respawns(ctx: TestContext) -> void:
	var player := ctx.spawn_player(1, Vector2(600, 100))
	var received: Array = []
	player.connect(
		"percentage_changed", func(index: int, pct: float) -> void: received.append([index, pct])
	)
	player.take_damage(0.0, Vector2(1, 0), 8.0)
	var fell := await _fall_past(ctx, player, 1100.0)
	ctx.check(fell, "player falls past y = 1100 with no floor")
	await ctx.step(12)
	ctx.check(player.global_position.y < 200.0, "crossing respawn_below_y 1200 returns to spawn")
	ctx.check_near(player.get("percentage"), 0.0, 0.01, "respawn resets percentage to 0")
	ctx.check(player.get("state") == Player.State.NORMAL, "respawn resets state to NORMAL")
	ctx.check(player.velocity.y < 200.0, "respawn resets velocity (was falling at 900 px/s)")
	ctx.check(
		received == [[1, 8.0], [1, 0.0]],
		"respawn emits percentage_changed(1, 0.0) after the hit's (1, 8.0) (got %s)" % [received]
	)


# i. Kept from the movement slice.
func test_attack_cannot_restart_during_recovery(ctx: TestContext) -> void:
	var fighters := await _face_off(ctx)
	var attacker := fighters[0]
	var hitbox_shape: CollisionShape2D = attacker.get_node("Hitbox/CollisionShape2D")
	ctx.press("p1_attack")
	await ctx.step(1)
	ctx.release("p1_attack")
	await ctx.step(9)
	ctx.check(hitbox_shape.disabled, "hitbox is off during recovery")
	ctx.press("p1_attack")
	await ctx.step(1)
	ctx.release("p1_attack")
	await ctx.step(3)
	ctx.check(hitbox_shape.disabled, "pressing attack during recovery does not start a new attack")


func test_player_two_uses_second_sprite(ctx: TestContext) -> void:
	var player := ctx.spawn_player(2, Vector2(600, 100))
	await ctx.step(1)
	var sprite: Sprite2D = player.get_node("Sprite2D")
	ctx.check(
		sprite.texture.resource_path.ends_with("fighter_p2.png"),
		"player_index 2 swaps to the orange fighter sprite"
	)


# j. A same-frame trade hits both fighters, whatever their order in the scene tree, and both
#    victims' stuns run on the same clock: the hit lands in frame A+3 (shape on at A+2, overlap
#    read one step later), the 20 stun frames are A+4..A+23, NORMAL is visible from A+24.
func test_same_frame_trade_hits_both(ctx: TestContext) -> void:
	ctx.make_floor(FLOOR_CENTER)
	var p1 := ctx.spawn_player(1, Vector2(500, STAND_Y))
	var p2 := _spawn_facing_left(ctx, 2, Vector2(540, STAND_Y))
	await ctx.step(3)
	ctx.check(p1.is_on_floor() and p2.is_on_floor(), "both fighters start grounded")
	ctx.press("p1_attack")
	ctx.press("p2_attack")
	await ctx.step(1)
	ctx.release("p1_attack")
	ctx.release("p2_attack")
	await ctx.step(8)
	ctx.check_near(p1.get("percentage"), 8.0, 0.01, "P1 takes P2's hit in a same-frame trade")
	ctx.check_near(p2.get("percentage"), 8.0, 0.01, "P2 takes P1's hit in a same-frame trade")
	ctx.check(p1.get("state") == Player.State.KNOCKBACK, "P1 is in KNOCKBACK after the trade")
	ctx.check(p2.get("state") == Player.State.KNOCKBACK, "P2 is in KNOCKBACK after the trade")
	ctx.check_near(p1.velocity.x, -166.4, 0.5, "P1 is launched away from P2 (0.8 * 260 * 0.8)")
	ctx.check_near(p2.velocity.x, 166.4, 0.5, "P2 is launched away from P1 (0.8 * 260 * 0.8)")
	await ctx.step(14)
	ctx.check(
		p1.get("state") == Player.State.KNOCKBACK and p2.get("state") == Player.State.KNOCKBACK,
		"both still stunned at the start of frame A+23 (stun counts A+4..A+23 for both)"
	)
	await ctx.step(1)
	ctx.check(
		p1.get("state") == Player.State.NORMAL and p2.get("state") == Player.State.NORMAL,
		"both regain control at the start of frame A+24"
	)


# k. The hitbox shape is on for exactly attack_active_frames (6) physics steps.
func test_hitbox_is_on_for_active_frames(ctx: TestContext) -> void:
	var fighters := await _face_off(ctx)
	var attacker := fighters[0]
	var hitbox_shape: CollisionShape2D = attacker.get_node("Hitbox/CollisionShape2D")
	ctx.press("p1_attack")
	await ctx.step(1)
	ctx.release("p1_attack")
	# Whole swing = 3 + 6 + 10 = 19 frames; sample a couple past its end.
	var enabled_frames := 0
	for _frame in range(21):
		if not hitbox_shape.disabled:
			enabled_frames += 1
		await ctx.step(1)
	ctx.check(
		enabled_frames == 6,
		(
			"hitbox shape is enabled at attack_active_frames (6) frame starts (actual %d)"
			% enabled_frames
		)
	)


# l. Falling off mid-swing: the respawned fighter has no live hitbox and no stale recovery.
func test_respawn_cancels_attack_in_progress(ctx: TestContext) -> void:
	var player := ctx.spawn_player(1, Vector2(600, 100))
	var hitbox_shape: CollisionShape2D = player.get_node("Hitbox/CollisionShape2D")
	var fell := await _fall_past(ctx, player, 1150.0)
	ctx.check(fell, "player falls past y = 1150 with no floor")
	# Falling at max_fall_speed (15 px/frame) it crosses respawn_below_y 1200 within 4 frames,
	# before or during the 3 startup frames of this swing.
	ctx.press("p1_attack")
	await ctx.step(1)
	ctx.release("p1_attack")
	var respawned := false
	for _frame in range(6):
		await ctx.step(1)
		if player.global_position.y < 200.0:
			respawned = true
			break
	ctx.check(respawned, "player respawns within 6 frames of the attack press")
	var stayed_disabled := hitbox_shape.disabled
	for _frame in range(8):
		await ctx.step(1)
		stayed_disabled = stayed_disabled and hitbox_shape.disabled
	ctx.check(stayed_disabled, "the swing started below the stage never turns its hitbox on")
	ctx.press("p1_attack")
	await ctx.step(3)
	ctx.release("p1_attack")
	ctx.check(
		not hitbox_shape.disabled,
		"a new attack right after the respawn turns the hitbox on in 3 frames"
	)
